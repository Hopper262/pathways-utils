#!/usr/bin/env perl
use strict;
use warnings 'FATAL' => 'all';
use JSON ();
use Encode ();
use MIME::Base64 ();

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

my @scrinfo;
for my $dref (sort { $a->[0] <=> $b->[0] } @datainfo)
{
  my ($off, $name, $id) = @$dref;
  next unless $name eq 'scri';
  
  SetReadSource($dataBlob) if defined $dataBlob;
  ReadPadding($off);
  my $origlen = ReadUint32();
  my $data = UnpackResource($origlen);
  
  push(@scrinfo, [ $id, length($data), $data ]);
}

my %corpse_types = (
  'nazi' => 'German soldier',
  'dude' => 'American soldier',
  'cubn' => 'person',
  'Naz5' => 'Mac developer',  # from A1 demo... just a guess on the type ;)
  );
my %opcode_types = (
  0 => 'testenv',
  1 => 'testvar',
  2 => 'say',
  3 => 'listen',
  4 => 'setvar',
  5 => 'stop',
  );

my %out_scrs;
for my $cref (sort { $a->[0] <=> $b->[0] } @scrinfo)
{
  my ($scr_id, $len, $data) = @$cref;
  next unless $len;
  SetReadSource($data);
  my $res_len = ReadUint16();
  next if $res_len == 0;
  
  my $num_strings = ReadUint16();
  next unless $num_strings > 0;
  
  my $str_offset = ReadUint16();
  ReadPadding(4);
  my $corp = ReadRaw(4);
  warn "Bad corpse type: $corp ($scr_id)\n" unless $corpse_types{$corp};
  
    
  my $pos = CurOffset();
  SetReadOffset($str_offset);
  my @strings = map { Encode::decode("MacRoman", $_) } split('\0', ReadRaw($len - $str_offset));
  warn "String mismatch: $num_strings vs. " . scalar(@strings) . "\n"
    if (scalar(@strings) != $num_strings);
  SetReadOffset($pos);
  
  my %ops;
  while (($pos = CurOffset()) < $str_offset)
  {
    my $opcode = ReadUint8();
    my $type = $opcode_types{$opcode};
    next unless $type;
    
    if ($type eq 'testenv')
    {
      ReadPadding(1);
      my $check = ReadRaw(4);
      my $goto = ComputeGoto($pos, ReadSint16(), $str_offset);
      $ops{$pos} = {
        'op' => 'testenv',
        'value' => $check,
        'goto' => $goto,
        };
    }
    elsif ($type eq 'testvar')
    {
      ReadPadding(1);
      my $mask = ReadUint16();
      my $value = ReadUint16();
      my $goto = ComputeGoto($pos, ReadSint16(), $str_offset);
      
      $ops{$pos} = {
        'op' => 'testvar',
        'mask' => $mask,
        'value' => $value,
        'goto' => $goto,
        };
    }
    elsif ($type eq 'say')
    {
      my $ct = ReadUint8();
      my $base = ReadUint16();
      my @says = ();
      for my $i (1..$ct)
      {
        my $which = $base + $i - 1;
        push(@says, $strings[$which]);
        warn "Bad string offset: $which ($scr_id, $pos)\n" if ($which >= $num_strings);
#         print sprintf("  %s\n", $strings[$which]);
      }
      $ops{$pos} = {
        'op' => 'say',
        'texts' => \@says,
        };
    }
    elsif ($type eq 'listen')
    {
      my $prompts = ReadUint8();
      my $hidden = ReadUint8();
      ReadPadding(1);
      my $base_str = ReadUint16();
      my @cases;
      for (my $i = 0; $i < ($prompts + $hidden); $i++)
      {
        my $which = $base_str + $i;
        warn "Bad string offset: $which ($scr_id, $pos)\n" if ($which >= $num_strings);
        my $wstr = $strings[$which];
        my $goto = ComputeGoto($pos, ReadSint16(), $str_offset);
        
        my %case = (
          'match' => $wstr,
          'goto' => $goto,
          );
        if ($i < $prompts)
        {
          $case{'prompt'} = 1;
        }
        
        push(@cases, \%case);
      }
      $ops{$pos} = {
        'op' => 'listen',
        'cases' => \@cases,
        };
    }
    elsif ($type eq 'setvar')
    {
      ReadPadding(1);
      my $mask = ReadUint16();
      my $value = ReadUint16();
      $ops{$pos} = {
        'op' => 'setvar',
        'mask' => $mask,
        'value' => $value,
        };
#       print sprintf(" set %04x mask %04x\n", $value, $mask);
    }
    elsif ($type eq 'stop')
    {
      ReadPadding(1);
      my $action = ReadRaw(4);
      warn "Bad stop data: $action\n" if ($action ne 'STOP');
      $ops{$pos} = {
        'op' => 'stop',
        };
    }
  }
  
  my @out_ops;
  {
    my @keys = sort { $a <=> $b } keys %ops;
    my $idx = 0;
    my %opmap = map { $_ => $idx++ } @keys;
    
    for my $pos (@keys)
    {
      my $info = $ops{$pos};
      if ($info->{'goto'})
      {
        $info->{'goto'} = $opmap{$info->{'goto'}};
        warn "Bad goto value ($pos, $scr_id)\n" unless defined $info->{'goto'};
      }
      if ($info->{'cases'})
      {
        for my $c (@{ $info->{'cases'} })
        {
          if ($c->{'goto'})
          {
            $c->{'goto'} = $opmap{$c->{'goto'}};
            warn "Bad goto value ($pos, $scr_id)\n" unless defined $c->{'goto'};
          }
        }
      }
      push(@out_ops, $info);
    }
  }
  
  next unless scalar @out_ops;
  
  $out_scrs{$scr_id} = {
    'desc' => $corpse_types{$corp},
    'ops' => \@out_ops,
    };
}

print JSON->new->ascii->encode(\%out_scrs);
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
  my ($len) = @_;
  
  return '' unless $len;
  my $data = ReadRaw(2);
  $len -= 2;
  
  my $k = 0;
  while ($len)
  {
    $data .= pack('C', ReadUint8() ^ $k);
    $len--;
    $k = (($k + 1) % 256);
  }
  
  return $data;
}

sub ComputeGoto
{
  my ($thisaddr, $offset, $endofdata) = @_;
  
  my $addr = $thisaddr + $offset;
  warn sprintf("Bad goto: %04x + %04x\n", $thisaddr, $offset)
    if ($addr >= $endofdata || $addr < 14);
  return $addr;
}
