#!/usr/bin/perl
use strict;
use warnings 'FATAL' => 'all';

my $slot = $ARGV[0] || 0;

# skip names
ReadPadding(10 * 128);

# get level offsets
my @offsets;
for my $i (0..9)
{
  for my $lev (0..24)
  {
    my $loff = ReadUint16();
    push(@offsets, $loff) if $slot == $i;
  }
}

# player data
for my $i (0..9)
{
  if ($slot == $i)
  {
    WriteThrough(2876);
  }
  else
  {
    ReadPadding(2876);
  }
}

my @leveldata;
# suck up all saved levels...
while (!ReadDone())
{
  push(@leveldata, ReadRaw(9112));
}

# ...then write them out in desired order
for my $lev (@offsets)
{
  WriteRaw($leveldata[$lev]);
}
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
sub ReadDone
{
  if (defined $BLOB)
  {
    return $BLOBlen > $BLOBoff;
  }
  return eof STDIN;
}

sub WriteUint32
{
  print pack('L>', Num(@_));
}
sub WriteSint32
{
  print pack('l>', Num(@_));
}
sub WriteUint16
{
  print pack('S>', Num(@_));
}
sub WriteSint16
{
  print pack('s>', Num(@_));
}
sub WriteUint8
{
  print pack('C', Num(@_));
}
sub WriteFixed
{
  my $num = Num(@_);
  WriteSint32(sprintf("%.0f", $num * 65536.0));
}  
sub WritePadding
{
  print "\0" x $_[0];
}
sub WriteRaw
{
  print @_;
}

sub Num
{
  my ($val, $default) = @_;
  $default = 0 unless defined $default;
  $val = $default unless defined $val;
  return $val + 0;
} # end Num

sub WriteThrough
{
  WriteRaw(ReadRaw(@_));
}
