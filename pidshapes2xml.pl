#!/usr/bin/perl
use strict;
use warnings 'FATAL' => 'all';
use XML::Writer ();
use Encode ();
use MIME::Base64 ();

my $out = XML::Writer->new('DATA_MODE' => 1, 'DATA_INDENT' => '  ', 'ENCODING' => 'us-ascii');
$out->startTag('shapes');

binmode STDIN;

# Read resource header
my $dataOff = ReadUint32();
my $mapOff = ReadUint32();
my $dataSize = ReadUint32();
my $mapSize = ReadUint32();

my $dataBlob;
if ($dataOff < $mapOff)
{
  ReadPadding($dataOff - CurOffset());
  $dataBlob = ReadRaw($dataSize);
  $dataOff = 0; # it will be, once we switch to reading this blob
}

ReadPadding($mapOff + 24 - CurOffset());
my $typeList = $mapOff + ReadUint16();
ReadPadding($typeList - CurOffset());
my $numTypes = ReadSint16() + 1;

my @typeinfo;
for my $ti (1..$numTypes)
{
  my $typename = ReadRaw(4);
  my $numRefs = ReadUint16() + 1;
  my $refOff = $typeList + ReadUint16();
  push(@typeinfo, [ $refOff, $typename, $numRefs ]);
}

my (@datainfo, %residsused);
for my $tref (sort { $a->[0] <=> $b->[0] } @typeinfo)
{
  my ($off, $name, $numRefs) = @$tref;
  ReadPadding($off - CurOffset());
  
  for my $ni (1..$numRefs)
  {
    my $id = ReadUint16();
    ReadPadding(2);
    my $itemOff = $dataOff + (ReadUint32() & 0xffffff);
    
    push(@datainfo, [ $itemOff, $name, $id ]);
    $residsused{$id} = 1;
    ReadPadding(4);
  }
}

my @collinfo;
for my $dref (sort { $a->[0] <=> $b->[0] } @datainfo)
{
  my ($off, $name, $id) = @$dref;
  next unless $name eq '.256';
  
  my $coll = $id - 128;
  my $colltype = 2;
  $colltype = 1 if $id > 191;
  
  SetReadSource($dataBlob) if defined $dataBlob;
  ReadPadding($off);
  my $origlen = ReadUint32();
  my $data = UnpackResource();
  
  push(@collinfo, [ 0, length($data), $coll, 8, $data, $colltype ]);
}

# SetReadSource($dataBlob) if defined $dataBlob;

for my $cref (sort { $a->[0] <=> $b->[0] } @collinfo)
{
  my ($off, $len, $coll, $depth, $data, $colltype) = @$cref;
  SetReadSource($data);
#   my $off = 0;
  my $pos = CurOffset();
#   next unless $off >= $pos;
#   ReadPadding($off - $pos);
  
#   $len = ReadUint32();
  
  $out->startTag('collection', 'index' => $coll, 'depth' => $depth);
  $out->emptyTag('definition', 'version' => 3, 'type' => $colltype);
  
  my $coll_off = CurOffset();
  # collection header
  {
    my $hcount = ReadSint16();
    my $hoff = ReadSint32();
    my $loff = ReadSint32();
    
    my $hcount2 = ($loff - $hoff) / 32;
    warn "Sequence count mismatch: $hcount vs. $hcount2\n" if ($hcount != $hcount2);
    
    my $boff = ReadSint32();
    
    my $lcount = ($boff - $loff) / 16;
    
    my $bsize = ReadSint32();
    
    my $chunksize = $boff + $bsize;
    warn "Bitmap: $len vs. $chunksize\n" if ($len != $chunksize);
    
    my $trans_color = ReadUint8();
    warn "Transparent index: $trans_color\n" if ($trans_color != 2);
    ReadPadding(1);
    my $cluts = ReadSint16();
    my $color_count = ReadSint16();
    my $coff = CurOffset();
    
    my (@frames, %btypes, %binfo, @bmaps);
    
    my @taginfo = (
      [ $coff, 'ctab', $cluts, $color_count, $trans_color ],
      [ $hoff, 'hlsh', $hcount ],
      [ $loff, 'llsh', $lcount ]);
    for my $tref (sort { $a->[0] <=> $b->[0] } @taginfo)
    {
      my ($off, $chunk, $count) = @$tref;
      next unless $off > 0;
      next unless $count > 0;
      $off += $coll_off;
      $pos = CurOffset();
      next unless $off >= $pos;
      ReadPadding($off - $pos);
      
      if ($chunk eq 'ctab')
      {
        my $trans_color = $tref->[4];
          
        my $color_count = $tref->[3];
        next unless $color_count > 0;
        for my $clut (0..($count - 1))
        {
          $out->startTag('color_table', 'index' => $clut);
          
          # transparent colors
          $out->emptyTag('color', 'value' => 0, 'red' => 0, 'green' => 0, 'blue' => 65535);
          $out->emptyTag('color', 'value' => 1, 'red' => 65535, 'green' => 0, 'blue' => 65535);
          $out->emptyTag('color', 'value' => 2, 'red' => 0, 'green' => 65535, 'blue' => 65535);
          for my $clr (1..$color_count)
          {
            
            my $val = ReadUint16();
            my $red = ReadUint16();
            my $green = ReadUint16();
            my $blue = ReadUint16();

#             warn "Color index mismatch: $val vs. $clr\n" if ($val != $clr + 2);

            $out->emptyTag('color', 'value' => $val, 'red' => $red, 'green' => $green, 'blue' => $blue);
          }
          $out->endTag('color_table');
        }
      }
      elsif ($chunk eq 'hlsh')
      {
        for my $i (0..($count - 1))
        {
          my $type = ReadSint16();
          my $flags = ReadUint16();
          my $x_mirror = ($flags & 0x4000) ? 1 : 0;
          my $on_floor = ($flags & 0x2000) ? 1 : 0; ## changes rendering?
          
          my $baseFrame = ReadSint16();
          my $windowFrame = ReadSint16();
          my $worldWidth = ReadSint16();
          my $worldHeight = ReadSint16();
          my $elevation = ReadSint16();
          my $windowOffset = ReadSint32();
          my $windowTop = ReadUint16();
          my $windowLeft = ReadUint16();
          my $windowBottom = ReadUint16();
          my $windowRight = ReadUint16();
          ReadPadding(6);
          
          ## Window variables only used in one instance,
          ## to add variation into a wall texture --
          ## I'm ignoring them here
          
          ## Base frame is index to "frame" (bitmap, in M2 terms)
          ## worldWidth = bitmap width * scale_factor
          ## elevation = -(y_origin * scale_factor)
          
          ## Welp, we need bitmap info to calculate the coords,
          ## so come back to this later
          push(@frames, [ $baseFrame, $type, $x_mirror, $on_floor, $worldWidth, $worldHeight, $elevation, $windowFrame, $windowOffset, $windowTop, $windowLeft, $windowBottom, $windowRight ]);
          
          ## But then, bitmap needs our type to decode properly,
          ## so we also save that
          $btypes{$baseFrame} = $type;
          if ($windowFrame)
          {
            $btypes{$windowFrame} = $type;
          }
        }
      }
      elsif ($chunk eq 'llsh')
      {
        for my $i (0..($count - 1))
        {
          my $boff2 = $boff + ReadSint32();
          my $width = ReadSint16();
          my $height = ReadSint16();
          my $lastWindow = ReadSint16();
#           warn "Last window: $lastWindow\n" if $lastWindow;
          ReadPadding(6);
          
          ## We'll look up pixel data and output it later
          push(@bmaps, [ $boff2, $i, $width, $height, $btypes{$i} ]);
          
          ## We'll also store our coords so we can export
          ## frame data from before
          $binfo{$i} = [ $width, $height ];
        }
      }
    }
    
    ## Deal with frames now
    my $fridx = -1;
    for my $fdata (@frames)
    {
      $fridx++;
      my ($idx, $type, $xmirror, $on_floor, $worldWidth, $worldHeight, $elevation, $winf, $wino, $wint, $winl, $winb, $winr) = @$fdata;
      
      my $bi = $binfo{$idx};
      unless ($bi)
      {
        warn "No frame size for $coll - $idx\n";
        next;
      }
      my ($width, $height) = @$bi;
      
      
      my $scale = 0;
      my ($origx, $origy, $keyx, $keyy, $wl, $wt, $wb, $wr, $wx, $wy) = (0, 0, 1, 1, 0, 0, 0, 0, 0, 0);
      
      if ($worldWidth || $worldHeight)
      {
        $scale = $worldWidth / $width;
        if ($worldHeight != ($height * $scale))
        {
          warn "Inconsistent scale factor ($worldWidth, $worldHeight) to ($width, $height)\n";
        }
        
        $origx = int($width / 2);
        $origy = $height + ($elevation / $scale);
        $wl = -$scale * $origx;
        $wt = $scale * $origy;
        $wr = $scale * ($width - $origx);
        $wb = -$scale * ($height - $origy);
        $wx = $scale * ($keyx - $origx);
        $wy = -$scale * ($keyy - $origy);
      }
      
      $out->emptyTag('low_level_shape', 'index' => $fridx,
            'x_mirror' => $xmirror, 'keypoint_obscured' => $on_floor,
            'bitmap_index' => $idx,
            'origin_x' => $origx, 'origin_y' => $origy,
            'key_x' => $keyx, 'key_y' => $keyy,
            'world_left' => $wl, 'world_right' => $wr,
            'world_top' => $wt, 'world_bottom' => $wb,
            'world_x0' => $wx, 'world_y0' => $wy,
            'window_frame' => $winf, 'window_offset' => $wino,
            'window_top' => $wint, 'window_left' => $winl,
            'window_bottom' => $winb, 'window_right' => $winr,
            );
    }
    
    ## Okay, time to grab the bitmap data
    for my $iref (sort { $a->[0] <=> $b->[0] } @bmaps)
    {
      my ($ioff, $index, $width, $height, $type) = @$iref;
      next unless $ioff > 0;
      $pos = CurOffset();
      next unless $ioff >= $pos;
      ReadPadding($ioff - $pos);
      
      my $column = ($type == 6) ? 0 : 1;
      
      my $bytes_row = ($column ? $height : $width);
#       $bytes_row = -1 if ($coll > 0 && ($colltype == 2 || $colltype == 4));
      my $transp = 1;
                    
      $out->startTag('bitmap', 'index' => $index,
            'width' => $width, 'height' => $height,
            'bytes_per_row' => $bytes_row,
            'column_order' => $column,
            'transparent' => $transp,
            'bit_depth' => 8,
            );
      
      # deal with data
      my $nul = chr(0);
      my $trans = chr($trans_color);
      my $rowct = $column ? $width : $height;
      my $rowlen = $column ? $height : $width;
      my $bdata = '';
      
      for my $col (1..$rowct)
      {
        my $linedata = ReadRaw($rowlen);
        $linedata =~ tr/\x02/\x00/;
        
        # pack into M2 format
#         if ($bytes_row < 0)  # RLE
#         {
#           $linedata =~ s/$nul+$//;
#           my $endlen = length($linedata);
#           $linedata =~ s/^$nul+//;
#           my $beglen = length($linedata);
#
#           my $last_row = $endlen;
#           my $first_row = $endlen - $beglen;
#           $bdata .= pack('s>s>', $first_row, $last_row);
#         }
        $bdata .= $linedata;
      }

      $out->characters(MIME::Base64::encode_base64($bdata));
      $out->endTag('bitmap');
    }
  }
  $out->endTag('collection');
}

$out->endTag('shapes');
$out->end();
exit;


sub ReadUint32
{
  return ReadPacked('L>', 4);
}
sub ReadSint32
{
  return ReadPacked('l>', 4);
}
sub ReadUint16
{
  return ReadPacked('S>', 2);
}
sub ReadSint16
{
  return ReadPacked('s>', 2);
}
sub ReadUint8
{
  return ReadPacked('C', 1);
}
sub ReadFixed
{
  my $fixed = ReadSint32();
  return $fixed / 65536.0;
}

our $BLOB = undef;
our $BLOBoff = 0;
our $BLOBlen = 0;
sub SetReadSource
{
  my ($data) = @_;
  $BLOB = $_[0];
  $BLOBoff = 0;
  $BLOBlen = defined($BLOB) ? length($BLOB) : 0;
}
sub SetReadOffset
{
  my ($off) = @_;
  die "Can't set offset for piped data" unless defined $BLOB;
  die "Bad offset for data" if (($off < 0) || ($off > $BLOBlen));
  $BLOBoff = $off;
}
sub CurOffset
{
  return $BLOBoff;
}
sub ReadRaw
{
  my ($size, $nofail) = @_;
  die "Can't read negative size" if $size < 0;
  return '' if $size == 0;
  if (defined $BLOB)
  {
    my $left = $BLOBlen - $BLOBoff;
    if ($size > $left)
    {
      return undef if $nofail;
      die "Not enough data in blob (offset $BLOBoff, length $BLOBlen)";
    }
    $BLOBoff += $size;
    return substr($BLOB, $BLOBoff - $size, $size);
  }
  else
  {
    my $chunk;
    my $rsize = read STDIN, $chunk, $size;
    $BLOBoff += $rsize;
    unless ($rsize == $size)
    {
      return undef if $nofail;
      die "Failed to read $size bytes";
    }
    return $chunk;
  }
}
sub ReadPadding
{
  ReadRaw(@_);
}
sub ReadPacked
{
  my ($template, $size) = @_;
  return unpack($template, ReadRaw($size));
}


sub UnpackResource
{
  my $datalen = ReadUint32();
  my ($d0, $d1, $d2, $d4) = (0, 0, 0, $datalen);
  my $data = '';
  
  while ($d4 > $d2)
  {
    $d0 = ReadUint8();
    if ($d0 >= 0x80)
    {
      $d0 -= 0x7f;
      $d2 += $d0;
      while ($d0) { $data .= ReadRaw(1); $d0--; }
    }
    else
    {
      $d0 += 3;
      $d1 = ReadRaw(1);
      $d2 += $d0;
      while ($d0) { $data .= $d1; $d0--; }
    }
  }
  
  return $data;
}
