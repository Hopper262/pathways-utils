#!/usr/bin/perl
use strict;
use warnings 'FATAL' => 'all';
use XML::Simple ();
use Data::Dumper ();
use Math::Trig ();

sub Usage() { die "Usage: $0 <level_number> <map.xml> <dpin.xml> <shapes.xml> > <level.obj>\n"; }

my ($levnum, $mapxml, $dpinxml, $shapesxml) = @ARGV;
Usage() unless (defined $levnum) && ($levnum =~ /^\d+$/);
my $xml = XML::Simple::XMLin($mapxml, 'KeyAttr' => [], 'ForceArray' => 1);
Usage() unless $xml;
my $map = $xml->{'level'};
Usage() unless $map;
our $mp = $map->[$levnum];
Usage() unless $mp;
$xml = XML::Simple::XMLin($dpinxml, 'KeyAttr' => [], 'ForceArray' => 1);
Usage() unless $xml;
my $dpin = $xml->{'level'};
Usage() unless $dpin;
our $ip = $dpin->[$levnum];
Usage() unless $ip;
$xml = XML::Simple::XMLin($shapesxml, 'KeyAttr' => [], 'ForceArray' => 1);
Usage() unless $xml;
my $shapes = $xml->{'collection'};
Usage() unless $shapes;

our @secinfo = ();
for my $row (0..31)
{
  my @row = ();
  for my $col (0..31)
  {
    push(@row, { 'open' => 0 });
  }
  push(@secinfo, \@row);
}

## populate sector info, with basic wall information
for my $sector (@{ $mp->{'sectors'}[0]{'sector'} })
{
  my $type = $sector->{'type'} || 0;
  my $open = ($type > 0) ? 1 : 0;
  my $col = $sector->{'col'} || 0;
  my $row = 31 - ($sector->{'row'} || 0);
  
  my $sref = $secinfo[$row][$col];
  $sref->{'open'} = $open;
  $sref->{'raw'} = $sector;
  
  for my $corner (qw(bl tl br tr))
  {
    if ((($sector->{'corner_' . $corner . '_type'} || 0) == 160) &&
        (($sector->{'corner_' . $corner . '_texture'} || 0) >= 0))
    {
      $sref->{$corner} = ($sector->{'corner_' . $corner . '_texture'} || 0);
    }
  }
  
  if ($open)
  {
    if ($sector->{'top_type'} &&
        ($sector->{'top_texture'} || 0) >= 0)
    {
      
      $sref->{'top'} = [
        ($sector->{'top_texture'} || 0),
        WallShort($sector->{'top_type'}, 'top') ];
    }
    if ($sector->{'left_type'} &&
        ($sector->{'left_texture'} || 0) >= 0)
    {
      $sref->{'left'} = [
        ($sector->{'left_texture'} || 0),
        WallShort($sector->{'left_type'}, 'left') ];
    }
  } else {
    # transfer walls from closed sectors to open ones
    if ($sector->{'top_type'} &&
        ($sector->{'top_texture'} || 0) >= 0)
    {
      my $neighbor = $secinfo[$row + 1][$col];
      $neighbor->{'bottom'} = [
        ($sector->{'top_texture'} || 0),
        WallShort($sector->{'top_type'}, 'bottom') ];
    }
    if ($sector->{'left_type'} &&
        ($sector->{'left_texture'} || 0) >= 0)
    {
      my $neighbor = $secinfo[$row][$col - 1];
      $neighbor->{'right'} = [ 
        ($sector->{'left_texture'} || 0),
        WallShort($sector->{'left_type'}, 'right') ];
    }
  }
}

my $collinfo = $mp->{'load_collections'}[0]{'load_collection'}[0];
my $colltype = $collinfo->{'collection'} . '-' . $collinfo->{'color_table'};

my %xy = (
  'wnw' => [ 0.00, 0.75 ], 'nw' => [ 0.00, 1.00 ], 'nnw' => [ 0.25, 1.00 ],
  'nne' => [ 0.75, 1.00 ], 'ne' => [ 1.00, 1.00 ], 'ene' => [ 1.00, 0.75 ],
  'ese' => [ 1.00, 0.25 ], 'se' => [ 1.00, 0.00 ], 'sse' => [ 0.75, 0.00 ],
  'ssw' => [ 0.25, 0.00 ], 'sw' => [ 0.00, 0.00 ], 'wsw' => [ 0.00, 0.25 ],
    );
my %floortc = (
  'wnw' => [ 0.25, 1.00 ], 'nw' => [ 0.00, 1.00 ], 'nnw' => [ 0.00, 0.75 ],
  'nne' => [ 0.00, 0.25 ], 'ne' => [ 0.00, 0.00 ], 'ene' => [ 0.25, 0.00 ],
  'ese' => [ 0.75, 0.00 ], 'se' => [ 1.00, 0.00 ], 'sse' => [ 1.00, 0.25 ],
  'ssw' => [ 1.00, 0.75 ], 'sw' => [ 1.00, 1.00 ], 'wsw' => [ 0.75, 1.00 ],
    );
my %ceiltc = %floortc;

my %cornerdirs = (
  'bl' => [ qw(sw ssw wsw) ],
  'tl' => [ qw(nw wnw nnw) ],
  'tr' => [ qw(ne nne ene) ],
  'br' => [ qw(se ese sse) ],
  );

my %walldirs = (
  'left'   => [ qw(nw wnw sw wsw) ],
  'top'    => [ qw(ne nne nw nnw) ],
  'bottom' => [ qw(sw ssw se sse) ],
  'right'  => [ qw(se ese ne ene) ],
  );

###
### Let's get to it!
IncludeMtl('pid.mtl');
Group('level-' . $levnum);

### Render each part separately, to help with .obj management

### Floors
Object('floor');
ForEachOpenSector(sub { my ($sref, $row, $col) = @_;

  my @floor = ();
  for my $corner (qw(bl br tr tl))
  {
    my $cd = $cornerdirs{$corner};
    if (exists $sref->{$corner})
    {
      push(@floor, $cd->[2], $cd->[1]);
    }
    else
    {
      push(@floor, $cd->[0]);
    }
  }
  Floor($row, $col, $colltype, @floor);

});
ForEachClosedSector(sub { my ($sref, $row, $col) = @_;

  for my $corner (qw(bl br tr tl))
  {
    my $cd = $cornerdirs{$corner};
    if (exists $sref->{$corner})
    {
      Floor($row, $col, $colltype, @$cd);
    }
  }

});

### Ceilings
Object('ceiling');
ForEachOpenSector(sub { my ($sref, $row, $col) = @_;

  for my $corner (qw(bl br tr tl))
  {
    my $cd = $cornerdirs{$corner};
    if (exists $sref->{$corner})
    {
      Ceiling($row, $col, $colltype, @$cd);
    }
  }

});
ForEachClosedSector(sub { my ($sref, $row, $col) = @_;

  my @ceil = ();
  for my $corner (qw(bl br tr tl))
  {
    my $cd = $cornerdirs{$corner};
    if (exists $sref->{$corner})
    {
      push(@ceil, $cd->[2], $cd->[1]);
    }
    else
    {
      push(@ceil, $cd->[0]);
    }
  }
  Ceiling($row, $col, $colltype, @ceil);

});

### Walls
my %opposite_corner = qw(bl tr br tl tr bl tl br);
for my $corner (qw(bl br tr tl))
{
  Object('walls-' . $corner);
  ForEachOpenSector(sub { my ($sref, $row, $col) = @_;
  
    my $tex = $sref->{$corner};
    return unless defined $tex;
    my $cd = $cornerdirs{$corner};
    CornerWall($row, $col, "$corner-$colltype", $tex, $cd->[1], $cd->[2]);
  
  });
  
  # corners face opposite direction in closed sectors
  my $opp = $opposite_corner{$corner};
  ForEachClosedSector(sub { my ($sref, $row, $col) = @_;

    my $tex = $sref->{$opp};
    return unless defined $tex;
    my $cd = $cornerdirs{$opp};
    CornerWall($row, $col, "$corner-$colltype", $tex, $cd->[2], $cd->[1]);
  
  });
}
for my $card (qw(top bottom left right))
{
  Object('walls-' . $card);
  ForEachOpenSector(sub { my ($sref, $row, $col) = @_;

    return unless exists $sref->{$card};
    my ($tex, $short_ccw, $short_cw) = @{ $sref->{$card} };
    my $wd = $walldirs{$card};
    EdgeWall($row, $col, "$card-$colltype", $tex,
        $short_cw  ? $wd->[3] : $wd->[2],
        $short_ccw ? $wd->[1] : $wd->[0],
        );

  });
}

## items from dpin
my $angle = -90;
Object('items');
for my $item (@{ $ip->{'items'}[0]{'item'} })
{
  next unless $item->{'visible_opaque'} || $item->{'visible_ir'} || $item->{'visible_transparent'};
  
  my $coll = $item->{'collection'};
  my $frame = $item->{'frame'};
  
  my $shp = IndexOf(IndexOf($shapes, $coll - 128)->{'low_level_shape'}, $frame);
  
  my $xcen = $item->{'x'} - 16;
  my $ycen = (32 - $item->{'y'}) - 16;
  my $leftw = $shp->{'world_left'} || 0;
  my $rightw = $shp->{'world_right'} || 0;
  my $toph = $shp->{'world_top'} || 0;
  my $both = $shp->{'world_bottom'} || 0;
  if ($both < 0)
  {
    $toph -= $both;
    $both = 0;
  }
  $leftw /= 1024;
  $rightw /= 1024;
  $toph /= 1024;
  $both /= 1024;
  
  my ($lxoff, $lyoff, $ldummy) = Math::Trig::cylindrical_to_cartesian(
                                  $leftw,
                                  Math::Trig::deg2rad($angle + 90), 0);
  my ($rxoff, $ryoff, $rdummy) = Math::Trig::cylindrical_to_cartesian(
                                  $rightw,
                                  Math::Trig::deg2rad($angle + 90), 0);
  
  Material("item-$levnum-$coll-$frame");
  Face([ Vertex($xcen + $lxoff, $ycen + $lyoff, $both), UV(0, 0) ],
       [ Vertex($xcen + $rxoff, $ycen + $ryoff, $both), UV(1, 0) ],
       [ Vertex($xcen + $rxoff, $ycen + $ryoff, $toph), UV(1, 1) ],
       [ Vertex($xcen + $lxoff, $ycen + $lyoff, $toph), UV(0, 1) ]);
}

exit;


sub ForEachSector
{
  my ($subref) = @_;
  
  for my $row (0..31) {
    for my $col (0..31) {
      $subref->($secinfo[$row][$col], $row, $col);
    }
  }
}
sub ForEachOpenSector
{
  my ($subref) = @_;
  
  for my $row (0..31) {
    for my $col (0..31) {
      my $sref = $secinfo[$row][$col];
      next unless $sref->{'open'};
      $subref->($sref, $row, $col);
    }
  }
}
sub ForEachClosedSector
{
  my ($subref) = @_;
  
  for my $row (0..31) {
    for my $col (0..31) {
      my $sref = $secinfo[$row][$col];
      next if $sref->{'open'};
      $subref->($sref, $row, $col);
    }
  }
}

sub WallShort
{
  my ($type, $which) = @_;
  
  my ($short_ccw, $short_cw) = (0, 0);
  
  if ($type == 128)
  {
    $short_ccw = $short_cw = 1;
  }
  elsif ($type == 64)
  {
    $short_ccw = 1 if ($which eq 'bottom' || $which eq 'left' );
    $short_cw  = 1 if ($which eq 'top'    || $which eq 'right');
  }
  elsif ($type == 96)
  {
    $short_ccw = 1 if ($which eq 'top'    || $which eq 'right');
    $short_cw  = 1 if ($which eq 'bottom' || $which eq 'left' );
  }
  return ($short_ccw, $short_cw);
}

sub Floor
{
  my ($row, $col, $colltype, @dirs) = @_;
  Material('floor-' . $colltype);
  BuildHorizontal($row, $col, 0, \%floortc, @dirs);
}

sub Ceiling
{
  my ($row, $col, $colltype, @dirs) = @_;
  Material('ceiling-' . $colltype);
  BuildHorizontal($row, $col, 1, \%ceiltc, @dirs);
}

sub DirVert
{
  my ($row, $col, $dir, $z) = @_;
  return Vertex($xy{$dir}[0] + $col - 16, $xy{$dir}[1] + $row - 16, $z);
}
  
sub BuildHorizontal
{
  my ($row, $col, $z, $tcref, @dirs) = @_;
  
  my @vs;
  for my $dir (@dirs)
  {
    my $v = DirVert($row, $col, $dir, $z);
    my $vt = UV(@{ $tcref->{$dir} });
    push(@vs, [ $v, $vt ]);
  }
  Face(@vs);
}

sub CornerWall
{
  Wall(@_);
}
sub EdgeWall
{
  Wall(@_);
}
sub Wall
{
  my ($row, $col, $colltype, $tex, @dirs) = @_;
  Material('wall-' . $colltype . '-' . $tex);
  BuildVertical($row, $col, @dirs);
}

sub BuildVertical
{
  my ($row, $col, @dirs) = @_;
  
  Face(
    [ DirVert($row, $col, $dirs[0], 0), UV(0, 0) ],
    [ DirVert($row, $col, $dirs[1], 0), UV(1, 0) ],
    [ DirVert($row, $col, $dirs[1], 1), UV(1, 1) ],
    [ DirVert($row, $col, $dirs[0], 1), UV(0, 1) ],
    );
}

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


our $last_mtl;
sub Material
{
  my ($mname) = @_;
  return unless defined $mname;
  return unless length $mname;
  
  $last_mtl = '' unless defined $last_mtl;
  unless ($mname eq $last_mtl)
  {
    print "usemtl $mname\n";
    $last_mtl = $mname;
  }
}

our %vlookup;
sub Vertex
{
  my ($x, $y, $z) = @_;
  
  my $vref = sprintf("%.2f %.2f %.2f", $x, $y, $z);
  return add_indexed(\%vlookup, $vref, "v %s\n");
}

our %uvlookup;
sub UV
{
  my ($u, $v) = @_;
  
  my $uvref = sprintf("%.2f %.2f", $u, $v);
  return add_indexed(\%uvlookup, $uvref, "vt %s\n");
}

our %normlookup;
sub Normal
{
  my ($x, $y, $z) = @_;
  
  my $nref = sprintf("%.2f %.2f %.2f", $x, $y, $z);
  return add_indexed(\%normlookup, $nref, "vn %s\n");
}

sub Face
{
  my (@vs) = @_;
  
  my @face = ('f');
  for my $vref (@vs)
  {
    if (ref $vref)
    {
      push(@face, join('/', @$vref));
    }
    else
    {
      push(@face, $vref);
    }
  }
  print join(' ', @face) . "\n";
}


sub add_indexed
{
  my ($hashref, $val, $printfmt) = @_;
  return $hashref->{$val} if exists $hashref->{$val};

  my $idx = 1 + scalar keys %$hashref;
  $hashref->{$val} = $idx;  
  print sprintf($printfmt, $val, $idx) if $printfmt;
  return $idx;
}

sub IncludeMtl
{
  my ($fname) = @_;
  print "mtllib $fname\n";
}
sub Group
{
  my ($groupname) = @_;
  print "g $groupname\n";
}
sub Object
{
  my ($objname, $smooth) = @_;
  $smooth = 1 unless defined $smooth;
  print "o $objname\n";
  print "s 1\n" if $smooth;
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


