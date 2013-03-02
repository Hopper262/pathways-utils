#!/usr/bin/env perl
use strict;
use warnings 'FATAL' => 'all';
use XML::Simple ();

sub Usage() { die "Usage: $0 <map.xml> <dpin.xml> > <pid.mtl>\n"; }

my ($mapxml, $dpinxml) = @ARGV;
my $xml = XML::Simple::XMLin($mapxml, 'KeyAttr' => [], 'ForceArray' => 1);
Usage() unless $xml;
our $map = $xml->{'level'};
Usage() unless $map;

$xml = XML::Simple::XMLin($dpinxml, 'KeyAttr' => [], 'ForceArray' => 1);
Usage() unless $xml;
our $dpin = $xml->{'level'};
Usage() unless $dpin;


# opposite directions, to flip walls in closed sectors
my %opp = qw(top bottom left right bl tr br tl tr bl tl br);

my %transparency = (
  'wall-bottom' => 0.3,
#   'wall-br' => 0.3,
#   'wall-right' => 0.3,
#   'wall-bl' => 0.3,
#   'ceiling' => 0.3,
  );

# monster color table info
our @monstercolors = (
  [ 129, 0 ], [ 130, 0 ], [ 131, 0 ], [ 132, 0 ], [ 133, 0 ],
  [ 139, 0 ], [ 140, 0 ], [ 134, 0 ], [ 135, 0 ], [ 136, 0 ],
  [ 142, 0 ], [ 141, 0 ], [ 133, 1 ], [ 139, 1 ], [ 137, 0 ],
  [ 129, 1 ], [ 142, 1 ] );


my (%wall_texture_specs, %item_texture_specs);
for my $level (0..24)
{
  my $mp = $map->[$level];
  unless ($mp)
  {
    warn "Failed to find level info for $level\n";
    last;
  }
  
  my $collinfo = $mp->{'load_collections'}[0]{'load_collection'}[0];
  my $colltype = $collinfo->{'collection'} . '-' . $collinfo->{'color_table'};
  
  my $sectorlist = $mp->{'sectors'}[0]{'sector'};
  for my $sector (@$sectorlist)
  {
    for my $opt (qw(top left corner_bl corner_br corner_tr corner_tl))
    {
      next unless $sector->{$opt . '_type'};
      my $tex = ($sector->{$opt . '_texture'} || 0);
      next if $tex < 0;
      
      my $dir = $opt;
      $dir =~ s/^corner_//;
      
      $dir = $opp{$dir} if (($sector->{'type'} || 0) == 0);
      
      $wall_texture_specs{$dir . '-' . $colltype . '-' . $tex} = 1;
    }
  }
  
  my %ctlookup = ();
  for my $cinfo (@{ $mp->{'load_collections'}[0]{'load_collection'} })
  {
    $ctlookup{$cinfo->{'collection'} + 128} = $cinfo->{'color_table'};
  }
  for my $minfo (@{ $mp->{'monsters'}[0]{'monster'} })
  {
    my $mcolor = $monstercolors[$minfo->{'type'}];
    $ctlookup{$mcolor->[0]} = $mcolor->[1];
  }
  
  my $ip = $dpin->[$level];
  unless ($ip)
  {
    warn "Failed to find dpin info for $level\n";
    next;
  }
  for my $item (@{ $ip->{'items'}[0]{'item'} })
  {
    next unless $item->{'visible_opaque'} || $item->{'visible_ir'} || $item->{'visible_transparent'};
    
    my $coll = $item->{'collection'};
    my $tab = $ctlookup{$coll} || 0;
    my $fr = $item->{'frame'};
    
    $item_texture_specs{$level . '-' . $coll . '-' . $tab . '-' . $fr} = 1;
  }
}

for my $spec (sort keys %wall_texture_specs)
{
  my ($dir, $coll, $tbl, $tex) = split('-', $spec);
  my $img = sprintf("images/%d/%d/frame%03d.png", 128 + $coll, $tbl, $tex);
  next unless -e $img;
  my $trans = $transparency{"wall-$dir"};
  $trans = 1.0 unless defined $trans;
  print <<END;
newmtl wall-$dir-$coll-$tbl-$tex
illum 0
d $trans
Ka 1.0 1.0 1.0
Kd 1.0 1.0 1.0
Ks 0.0 0.0 0.0
map_Kd $img

END
}

for my $spec (sort keys %item_texture_specs)
{
  my ($level, $coll, $tbl, $tex) = split('-', $spec);
  my $img = sprintf("images/%d/%d/frame%03d.png", $coll, $tbl, $tex);
  next unless -e $img;
  print <<END;
newmtl item-$level-$coll-$tex
illum 0
d 0.99
Ka 1.0 1.0 1.0
Kd 1.0 1.0 1.0
Ks 0.0 0.0 0.0
map_Kd $img

END
}


# DOORS
# Doors have a 'type' field that factors into the textures used,
# but I don't see anything directly specifying the frames.

# translate map's door "texture" to frames in first loaded collection
my @doorframes = (
    [ 64, [ 12, 13 ] ],  # 0
    [ 64, [ 12, 13 ] ],  # 1 (Pipes doors - just like 0)
    [  0, [  0,  0 ] ],  # unused
    [ 66, [  9, 10 ] ],  # 3 (Silver door)
    [ 66, [ 12, 13 ] ],  # 4
    [ 66, [  6,  7 ] ],  # 5 (Gold door)
    [ 65, [ 11, 12 ] ],  # 6
  );


# 		None=0,						// Nothing rendered (both wall and corner)
# 		SwitchableWallCorner=1,		// Corner: everywhere in "The Labyrinth"
# 		Wall=32,					// Full-length wall
# 		Wall_FancyCorners=33,		// Full-length wall with fancy corners
# 		Wall_ShortLow=64,			// Wall that is short on -x/-y end
# 		Wall_ShortHigh=96,			// Wall that is short on +x/+y end
# 		Wall_ShortBoth=128,			// Wall that is short on both ends
# 		CutoffCorner=160			// Corner with short diagonal wall nearby

# Floor/ceiling (0/1, in that order)
# Orientation: top edge is west, left edge north, right edge south
# (floor is flipped, when seen from above)
# (ceiling is not flipped, seen from below)
# uses colors from app clut
# Ground Floor uses 195, 129
# Labyrinth uses 198, 132?
# LOS uses 199, 135
# HHCC uses 202, 134
# Who Else uses 199, 135

# gradients 130 and 135 are the same

# floor/ceiling seems to be linked to wall collection/clut
my %floortex = (
    '64-0' => [ 67, [ 0.1, 0.1, 0.1 ] ],
    '64-1' => [ 67, [ 0.1, 0.1, 0.1 ] ],
    '64-2' => [ 68, [ 0.2, 0.1, 0.1 ] ],
    
    '65-0' => [ 71, [ 0.2, 0.1, 0.1 ] ],
    '65-1' => [ 71, [ 0.2, 0.1, 0.1 ] ],
    '65-2' => [ 73, [ 0.2, 0.1, 0.1 ] ],
    '65-3' => [ 72, [ 0.2, 0.1, 0.1 ] ],
    
    '66-0' => [ 69, [ 0.1, 0.1, 0.2 ] ],
    '66-1' => [ 69, [ 0.2, 0.2, 0.1 ] ],
    '66-2' => [ 74, [ 0.1, 0.2, 0.1 ] ],
    '66-3' => [ 70, [ 0.1, 0.2, 0.2 ] ],
  );



###
###
###

for my $colltype (sort keys %floortex)
{
  my $ref = $floortex{$colltype};
  my $diffuse = sprintf("%.1f %.1f %.1f", @{ $ref->[1] });
  my %img = (
    'floor' => sprintf("images/%d/0/frame%03d.png", 128 + $ref->[0], 0),
    'ceiling' => sprintf("images/%d/0/frame%03d.png", 128 + $ref->[0], 1),
    );

  for my $which (sort keys %img)
  {
#     next unless -e $img{$which};
    my $trans = $transparency{$which};
    $trans = 1.0 unless defined $trans;
    print <<END;
newmtl $which-$colltype
illum 0
d $trans
Ka $diffuse
Kd $diffuse
Ks 0.0 0.0 0.0
map_Kd $img{$which}

END
  }
}
