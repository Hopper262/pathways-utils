#!/usr/bin/perl
use strict;
use warnings 'FATAL' => 'all';
use XML::Writer ();
use Encode ();
use FindBin();

require $FindBin::Bin . '/io.subs';

my ($vers) = $ARGV[0] || 'full20';

# read map
my (@leveldata);
binmode STDIN;
while (!eof(STDIN))
{
  my $data;
  read(STDIN, $data, 16834);
  push(@leveldata, $data);
}

my $xmldata;
my $out = XML::Writer->new('OUTPUT' => \$xmldata, 'DATA_MODE' => 1, 'DATA_INDENT' => '  ', 'ENCODING' => 'us-ascii');
$out->startTag('pid_map');

for (my $level_idx = 0; $level_idx < scalar @leveldata; $level_idx++)
{
  SetReadSource($leveldata[$level_idx]);
  
  my $namesize = ReadUint8();
  my $name = Encode::decode("MacRoman", ReadRaw($namesize));
  ReadPadding(127 - $namesize);
  
  my $levelnum = ReadSint32();
  warn "Level mismatch: $levelnum vs. $level_idx\n" if ($levelnum != $level_idx);
  
  my $height = ReadSint16() / 10;
  
  my $startx = ReadSint32();
  my $starty = ReadSint32();
  
  $out->startTag('level', 'index' => $level_idx, 'name' => $name, 'height' => $height);
  
  # textures
  $out->startTag('load_collections');
  for my $ltex_idx (0..7)
  {
    my $tdesc = ReadUint16();
    next if $tdesc == 0xFFFF;
    my $var = ($tdesc >> 12);
    my $set = ($tdesc & 0x0FFF);
    $out->emptyTag('load_collection', 'index' => $ltex_idx, 'collection' => $set, 'color_table' => $var);
  }
  $out->endTag('load_collections');
  
  $out->startTag('doors');
  for my $door_idx (0..14)
  {
    my $x = ReadSint16();
    my $y = ReadSint16();
    my $dir = ReadSint16();
    my $tex = ReadSint16();
    
    next if $dir < 0;
    $out->emptyTag('door', 'index' => $door_idx, 'direction' => $dir, 'x' => $x, 'y' => $y, 'texture' => $tex);
  }
  $out->endTag('doors');
  
  $out->startTag('level_changes');
  for my $change_idx (0..19)
  {
    my $type = ReadSint16();
    my $lev = ReadSint16();
    my $x = ReadSint16();
    my $y = ReadSint16();
    
    next if $type < 0;
    $out->emptyTag('level_change', 'index' => $change_idx, 'type' => $type, 'level' => $lev, 'x' => $x, 'y' => $y);
  }
  $out->endTag('level_changes');
  
  $out->startTag('monsters');
  for my $mon_idx (0..2)
  {
    # tbd - PID_Monster
    my $type = ReadSint16();
    my $freq = ReadSint16();
    
    next if $type < 0;
    $out->emptyTag('monster', 'index' => $mon_idx, 'type' => $type, 'frequency' => $freq);
  }
  $out->endTag('monsters');
  
  $out->startTag('sectors');
  for my $row (0..31)
  {
    for my $col (0..31)
    {
      
      my @wattrs;
      for my $wtype (qw(top left corner_tr corner_tl corner_br corner_bl))
      {
        my $type = ReadUint8();
        my $tex = ReadUint8();
        my $texflag = 0;
        if ($tex > 127)
        {
          $texflag = 1;
          $tex -= 128;
        }
        if ($tex > 63)
        {
          $tex -= 128;
        }
        push(@wattrs, $wtype . '_type' => $type) if ($type != 0);
        push(@wattrs, $wtype . '_textureflag' => $texflag) if ($texflag != 0);
        push(@wattrs, $wtype . '_texture' => $tex) if ($tex != 0);
      }
      
      my $item = ReadSint16();
      my $type = ReadUint8();
      my $addl = ReadUint8();
      
      next if ($type < 1 && !scalar(@wattrs)); # skip void, so our file isn't so huge
     
     $out->emptyTag('sector', 'col' => $col, 'row' => $row, 'type' => $type, 'extra' => $addl, 'item' => $item, @wattrs);      
    }
  }
  $out->endTag('sectors');
  
  $out->endTag('level');
}
$out->endTag('pid_map');
$out->end();

print $xmldata;
exit;
