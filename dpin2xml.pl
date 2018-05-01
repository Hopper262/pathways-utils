#!/usr/bin/perl
use strict;
use warnings 'FATAL' => 'all';
use XML::Writer ();
use Encode ();

my $a1demo = $ARGV[0] || 0;

my $out = XML::Writer->new('DATA_MODE' => 1, 'DATA_INDENT' => '  ', 'ENCODING' => 'us-ascii');
$out->startTag('dpin');

binmode STDIN;

### Player state
# unless ($a1demo)
{
  my $sig = ReadUint32();
  warn "Signature: $sig\n" unless $sig == ($a1demo ? 394932 : 789308);
  my $slot_idx = ($a1demo ? 0 : ReadSint16());
  
  my $time = ReadUint32();
  my $points = ReadUint16();
  my $treasure = ReadUint32();
  ReadPadding(64); # unknown2
  ReadPadding(1); # prob. high byte of lefty stored as short
  my ($lefty) = ReadBits(1);
  ReadPadding(2); # unknown3
  
  $out->startTag('player', 'time' => $time, 'points' => $points, 'treasure' => $treasure, 'left_handed' => $lefty);
  
  my $level = ReadSint16();
  my $levelx = ReadUint32() / 1024;
  my $levely = ReadUint32() / 1024;
  my $facing = ReadSint16();
  $out->emptyTag('location', 'level' => $level, 'x' => $levelx, 'y' => $levely, 'direction' => $facing);
  
  my $health = ReadSint16();
  my $maxhealth = ReadSint16();
  $out->emptyTag('health', 'current' => $health, 'max' => $maxhealth);
  
  $out->startTag('weapon_proficiencies');
  for my $weapon (0..6)
  {
    my $kills = ReadSint16();
    my $prof = ReadSint16();
    my $un = ReadSint16();
    warn "Weapon proficiency unknown: $un\n" unless $un == 0;

    $out->emptyTag('weapon', 'index' => $weapon, 'kills' => $kills, 'proficiency' => $prof) if ($kills || $prof);
  }
  $out->endTag('weapon_proficiencies');
  
  ReadPadding(44); # Unknown4
  
  unless ($a1demo)
  {
    my $dam_taken = ReadUint32();
    my $dam_given = ReadUint32();
    $out->emptyTag('damage', 'taken' => $dam_taken, 'inflicted' => $dam_given);
    
    $out->startTag('weapon_shots');
    for my $weapon (0..4)
    {
      my $shots = ReadUint32();
      $out->emptyTag('weapon', 'index' => $weapon, 'shots' => $shots) if $shots;
    }
    $out->endTag('weapon_shots');
    $out->startTag('weapon_hits');
    for my $weapon (0..4)
    {
      my $hits = ReadUint32();
      $out->emptyTag('weapon', 'index' => $weapon, 'hits' => $hits) if $hits;
    }
    $out->endTag('weapon_hits');
    
    $out->startTag('monster_kills');
    for my $weapon (0..16)
    {
      my $kills = ReadUint32();
      $out->emptyTag('monster', 'index' => $weapon, 'kills' => $kills) if $kills;
    }
    $out->endTag('monster_kills');
    
    ReadPadding(4); # Unknown4b
  }
  
  my ($goggles) = ReadUint8(1);
  ReadPadding(2); # always 0x0100 ?
  my ($flashlight) = ReadUint8(1);
  $out->emptyTag('vision', 'ir_goggles' => $goggles, 'flashlight' => $flashlight);
  
  ReadPadding(8); # Unknown4c
  my $poison = ReadSint16();
  ReadPadding(10) unless $a1demo; # Unknown4d,e
  $out->emptyTag('ailments', 'poison_rate' => $poison);
  
  my @trigger_flags = ReadBits(128);
  $out->startTag('triggers_set');
  for my $i (0..127)
  {
    $out->emptyTag('trigger_set', 'index' => $i) if $trigger_flags[$i];
  }
  $out->endTag('triggers_set');
  
  ReadPadding(16); # unused triggers?
  
  my @item_flags = ReadBits(80);
  $out->startTag('items_taken');
  for my $i (0..79)
  {
    $out->emptyTag('item_taken', 'index' => $i) if $item_flags[$i];
  }
  $out->endTag('items_taken');
  
  ReadPadding(30); # Unknown4g,h
  
  my $cur_crystal = ReadSint16();
  my $charge = ReadSint16();
  ReadPadding(2); # Unknown5
  my $cur_weapon = ReadSint16();
  my $weapon_anim = ReadSint16();
  $out->emptyTag('items_in_hand', 'crystal' => $cur_crystal, 'crystal_charge' => $charge, 'weapon' => $cur_weapon, 'weapon_status' => $weapon_anim);
  
  ReadPadding($a1demo ? 18 : 22);  # No idea if this is the right spot...
  
  $out->startTag('corpse_variables');
  for my $i (128..177)
  {
    my $corpse_var = ReadUint16();
    $out->emptyTag('corpse_variable', 'index' => $i, 'value' => $corpse_var) if $corpse_var != 0;
  }
  $out->endTag('corpse_variables');
  
  # active monsters
  {
    my $mon_count = ReadUint16();
    $out->startTag('active_monsters', 'total' => $mon_count) if $mon_count;
    
    # skip for now, we don't really have them figured out
    ReadPadding(8 * 2 * 12);
    ReadPadding(2);
    ReadPadding(4 * 2 * 12);
    
    $out->endTag('active_monsters') if $mon_count;
  }
  
  my $first_inv = ReadSint16();
  $out->startTag('inventory', 'start' => $first_inv);
  
  for my $i (0..($a1demo ? 127 : 255))
  {
    my $type = ReadSint16();
    my $act = ReadSint16();
    my $cont = ReadSint16();
    my $next = ReadSint16();
    
    next if $type < 0;
    $out->emptyTag('item', 'index' => $i, 'type' => $type, 'active' => $act, 'contains' => $cont, 'next' => $next);
  }
  $out->endTag('inventory');

  $out->endTag('player');
}

## Level state
for (my $level_idx = 0; !ReadDone(); $level_idx++)
{
  my ($cached, $cached_monct) = (0, 0);
  if ($level_idx == 3)
  {
    $cached = 1;
    $cached_monct = ReadSint16();
    if ($cached_monct == 0)
    {
      ReadPadding(4);
      last if ReadDone();
    }
  }
    
  $out->startTag('level', 'index' => $level_idx);
  
  $out->startTag('monsters');
  my $mon_ct = $cached ? $cached_monct : ReadSint16();
  for my $mon_idx (0..59)
  {
    if ($mon_idx >= $mon_ct)
    {
      ReadPadding($cached ? 4 : 8);
      next;
    }
    $cached = 0;
    
    my $type = ReadSint16();
    my $health = ReadSint16();
    my $unused = ReadSint16();
#     warn "MonsterState unused: $unused\n" if $unused;
    my $item_id = ReadSint16();
    $out->emptyTag('monster', 'index' => $mon_idx, 'type' => $type, 'health' => $health, 'item' => $item_id);
  }
  $out->endTag('monsters');
  
  my %valid_pickups;
  
  $out->startTag('assigns');
  my $assign_ct = ReadSint16();
  for my $assign_idx (0..29)
  {
    if ($assign_idx >= $assign_ct)
    {
      ReadPadding(4);
      next;
    }
    
    my $item_id = ReadSint16();
    my $pickup_id = ReadSint16();
    $valid_pickups{$pickup_id} = 1;
    $out->emptyTag('assign', 'index' => $assign_idx, 'item' => $item_id, 'pickup' => $pickup_id);
  }
  $out->endTag('assigns');
  
  $out->startTag('pickups');
  for my $pickup_idx (0..39)
  {
    my $type = ReadSint16();
    my $act = ReadSint16();
    my $quant = ReadSint16();
    my $contain = ReadSint16();
    
    $out->emptyTag('pickup', 'index' => $pickup_idx, 'type' => $type, 'activity' => $act, 'quantity' => $quant, 'contains' => $contain);
    next if $type < 0;
  }
  $out->endTag('pickups');
  
  $out->startTag('door_states');
  for my $u1_idx (0..14)
  {
    my $ulong = ReadSint32();
    next if $ulong == 0;
    $out->emptyTag('door_state', 'index' => $u1_idx, 'closed' => $ulong);
  }
  $out->endTag('door_states');
  
  $out->startTag('items');
  for my $item_idx (0..($a1demo ? 399 : 499))
  {
    my $xpos = ReadSint32();
    my $ypos = ReadSint32();
    
    my $collbit = ReadUint16();
    my $collection = (($collbit >> 7) & 0xff);
    my $frame = ($collbit & 0x7f);
    

    my $un3byte = ReadUint8();
    warn "Unknown3: $un3byte\n" if ($un3byte & 0x1F);
    my $seen  = ($un3byte & 0x20) ? 1 : 0;
    my $solid = ($un3byte & 0x40) ? 1 : 0;
    my $sleep = ($un3byte & 0x80) ? 1 : 0;
    
    my $visbyte = ReadUint8();
    warn "Visibility: $visbyte\n" if ($visbyte & 0xF8);
    my $vis_trans  = ($visbyte & 0x01) ? 1 : 0;
    my $vis_ir     = ($visbyte & 0x02) ? 1 : 0;
    my $vis_opaque = ($visbyte & 0x04) ? 1 : 0;
    
    my $unshort = ReadSint16();
    warn "Item unknown5: $unshort\n" if $unshort;
    my $next = ReadSint16();
    
    next if ($next == -2);
    $out->emptyTag('item', 'index' => $item_idx, 'x' => $xpos / 1024, 'y' => $ypos / 1024, 'next' => $next, 'collection' => $collection, 'frame' => $frame, 'seen' => $seen, 'solid' => $solid, 'asleep' => $sleep, 'visible_opaque' => $vis_opaque, 'visible_ir' => $vis_ir, 'visible_transparent' => $vis_trans);
  }
  $out->endTag('items');
  
  $out->startTag('mapped_sectors');
  for my $row (0..31)
  {
    my $rowdata = unpack('b32', ReadRaw(4));
    for my $col (0..31)
    {
      my $seen = substr($rowdata, $col, 1);
      next unless $seen;
      $out->emptyTag('mapped_sector', 'col' => $col, 'row' => $row);
    }
  }
  $out->endTag('mapped_sectors');
  
  $out->endTag('level');
}

$out->endTag('dpin');
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
sub ReadBits
{
  my ($bits) = @_;
  my $bytes = int(($bits + 7)/8);
  return map { $_ + 0 } split(//, ReadPacked('b' . $bits, $bytes));
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
