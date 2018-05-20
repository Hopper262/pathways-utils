#!/usr/bin/env perl
use strict;
use warnings 'FATAL' => 'all';
use XML::Simple ();
use Image::Magick ();

our $imgdir = $ARGV[0];
die "Usage: $0 <images-dir> <map.xml>\n" unless -d $imgdir;

my $xml = XML::Simple::XMLin($ARGV[1], 'KeyAttr' => [], 'ForceArray' => 1);
die "Usage: $0 <images-dir> <map.xml>\n" unless $xml;
our $map = $xml->{'level'};
die "Usage: $0 <images-dir> <map.xml>\n" unless $map;


my $dim = 8; # pixels per grid square; must match input images

# Sector types:
# Void,				// Inaccessible
# Normal,				// Accessible, but nothing special
# Door,				// (self-explanatory)
# ChangeLevel,		// Change levels here
# DoorTrigger,		// Triggers doors opening/closing
# SecretDoor,			// What triggers them?
# Corpse,				// You can talk to these
# Pillar,				// Pillar in the middle -- can't walk through
# OtherTrigger,		// Not exactly sure what this one does
# Save,				// Can save game here

my @sectorinfo = (
    [ Img("190/0/bitmap000.png"),    # void
      Img("190/0/bitmap001.png"),
      Img("190/0/bitmap002.png"),
      Img("190/0/bitmap003.png"),
      Img("190/0/bitmap004.png"),
      Img("190/0/bitmap005.png"),
      Img("190/0/bitmap006.png"),
      Img("190/0/bitmap007.png"),
      Img("190/0/bitmap008.png"),
      Img("190/0/bitmap009.png"),
      Img("190/0/bitmap010.png"),
      Img("190/0/bitmap011.png"),
      Img("190/0/bitmap012.png"),
      Img("190/0/bitmap013.png"),
      Img("190/0/bitmap014.png"),
      Img("190/0/bitmap015.png") ],
    Img("190/0/bitmap019.png"),     # normal
    [ Img("190/0/bitmap022.png"),   # door
      Img("190/0/bitmap021.png"),
      Img("190/0/bitmap022.png"),
      Img("190/0/bitmap021.png") ],
    [ Img("190/0/bitmap017.png"),   # ladder/teleport
      Img("190/0/bitmap016.png"),
      Img("190/0/bitmap020.png"),
      Img("190/0/bitmap020.png") ],
    Img("190/0/bitmap019.png"),     # door trigger
    [ Img("190/0/bitmap019.png"),   # secret door
      Img("190/0/bitmap019.png"),
      Img("190/0/bitmap019.png"),
      Img("190/0/bitmap019.png") ],
    [ Img("190/0/bitmap023.png"),   # corpse
      Img("190/0/bitmap025.png") ],
    Img("190/0/bitmap018.png"),     # pillar
    Img("190/0/bitmap019.png"),     # other trigger
    Img("190/0/bitmap024.png"),     # save rune
  );

for my $level (0..24)
{
  my $mp = $map->[$level];
  unless ($mp)
  {
#     warn "Failed to find level info for $level\n";
    last;
  }

  my $doorlist = $mp->{'doors'}[0]{'door'};
  my $ladderlist = $mp->{'level_changes'}[0]{'level_change'};
  my $sectorlist = $mp->{'sectors'}[0]{'sector'};
  
  # initialize map
  my $base = Image::Magick->new('size' => (34 * $dim) . 'x' . (34 * $dim));
  $base->ReadImage('canvas:white');
  
  my @grid;
  for my $row (0..33)
  {
    $grid[$row] = [];
    for my $col (0..33)
    {
      $grid[$row][$col] = 0;
      $base->Composite('image' => $sectorinfo[1], 'x' => $col * $dim, 'y' => $row * $dim, 'compose' => 'over');
    }
  }
  
  # deal with non-void sectors
  for my $sector (@$sectorlist)
  {
    my $type = $sector->{'type'};
    next if $type == 0;
    
    my $col = $sector->{'col'} + 1;
    my $row = $sector->{'row'} + 1;
    $grid[$row][$col] = $type;
    
    my $bitmap = $sectorinfo[$type];
    if ($type == 2) # door
    {
      my $door = IndexOf($doorlist, $sector->{'extra'});
      die "Door not found at $level ($col, $row)" unless $door;
      $bitmap = $bitmap->[$door->{'direction'}];
    }
    elsif ($type == 3) # level change
    {
      my $ladder = IndexOf($ladderlist, $sector->{'extra'});
      $bitmap = $bitmap->[$ladder->{'type'}];
      $bitmap = $sectorinfo[1] unless $bitmap; # broken teleporter on lv22
    }
    elsif ($type == 5) # secret door
    {
      $bitmap = $bitmap->[$sector->{'extra'}];
    }
    elsif ($type == 6) # corpse
    {
      $bitmap = $bitmap->[$sector->{'extra'} < 0 ? 1 : 0 ];
    }
    
    if ($bitmap != $sectorinfo[1])
    {
      $base->Composite('image' => $bitmap, 'x' => $col * $dim, 'y' => $row * $dim, 'compose' => 'over');
    }
  }
  
  # detect unreachable void sectors
  my @unreachable;
  for my $row (1..32)
  {
    for my $col (1..32)
    {
      my $type = $grid[$row][$col];
      next unless $type == 0;
      
      next unless
        $grid[$row - 1][$col - 1] == 0 &&
        $grid[$row + 0][$col - 1] == 0 &&
        $grid[$row + 1][$col - 1] == 0 &&
        $grid[$row - 1][$col + 0] == 0 &&
        $grid[$row + 1][$col + 0] == 0 &&
        $grid[$row - 1][$col + 1] == 0 &&
        $grid[$row + 0][$col + 1] == 0 &&
        $grid[$row + 1][$col + 1] == 0;
      
      push(@unreachable, [ $row, $col ]);
    }
  }
  
  # mark borders as unreachable
  for my $row (0..33)
  {
    for my $col (0, 33)
    {
      push(@unreachable, [ $row, $col ]);
    }
  }
  for my $col (1..32)
  {
    for my $row (0, 33)
    {
      push(@unreachable, [ $row, $col ]);
    }
  }
  
  # change unreachable to open, to mimic map behavior
  for my $ref (@unreachable)
  {
    my ($row, $col) = @$ref;
    $grid[$row][$col] = 1;
  }
  
  # finally, deal with walls (remaining void)
  for my $row (1..32)
  {
    for my $col (1..32)
    {
      my $type = $grid[$row][$col];
      next unless $type == 0;
      
      my $which = 0;
      $which += 1 if ($grid[$row - 1][$col] == 0);
      $which += 2 if ($grid[$row][$col - 1] == 0);
      $which += 4 if ($grid[$row + 1][$col] == 0);
      $which += 8 if ($grid[$row][$col + 1] == 0);
      my $bitmap = $sectorinfo[0][$which];

      $base->Composite('image' => $bitmap, 'x' => $col * $dim, 'y' => $row * $dim, 'compose' => 'over');
    }
  }
  
  my $err = $base->Write(sprintf('level%03d.png', $level));
  die $err if $err;
}

sub IndexOf
{
  my ($ref, $idx) = @_;
  
  for my $r (@$ref)
  {
    if ($r->{'index'} == $idx)
    {
      return $r;
    }
  }
  return undef;
}

sub Img
{
  my ($path) = @_;
  
  my $img = Image::Magick->new() or die;
  my $err = $img->Read("$imgdir/$path");
  die $err if $err;
  return $img;
}
