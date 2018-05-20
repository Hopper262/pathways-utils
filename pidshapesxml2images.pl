#!/usr/bin/perl
use strict;
use warnings 'FATAL' => 'all';
use Image::Magick ();
use XML::Simple ();
use MIME::Base64 ();

my $basedir = $ARGV[0] || 'images';
mkdir $basedir;

my $usage = "Usage: $0 [image-dir] < <shapes.xml>\n";
my $xml = XML::Simple::XMLin('-', 'KeyAttr' => [], 'ForceArray' => 1);
die $usage unless $xml;
our $colls = $xml->{'collection'};
die $usage unless $colls;

for my $coll (@$colls)
{
  my $id = $coll->{'index'} + 128;
  my $colldir = "$basedir/$id";
  mkdir $colldir;
  
  for my $ct (@{ $coll->{'color_table'} })
  {
    my $tab = $ct->{'index'};
    my $tabdir = "$colldir/$tab";
    mkdir $tabdir;
    
    my @clrs;
    for my $color (@{ $ct->{'color'} })
    {
      my $ci = $color->{'value'};
      $clrs[$ci] = [ ($color->{'red'} || 0) / 65535,
                     ($color->{'green'} || 0) / 65535,
                     ($color->{'blue'} || 0) / 65535,
                     ($ci < 3 ? 1.0 : 0.0) ];
    }
    
    my @images;
    for my $bm (@{ $coll->{'bitmap'} })
    {
      my $bi = $bm->{'index'};
      my $fname = sprintf("$tabdir/bitmap%03d.png", $bi);
      
      my $width = $bm->{'width'};
      my $height = $bm->{'height'};
      my $img = $images[$bi] = Image::Magick->new();
      $img->Set('size' => $width . 'x' . $height);
      $img->Read('canvas:rgb(0,0,255,0)');
      $img->Set('matte' => 'True');
      $img->Set('alpha' => 'On');
      
      my $column = $bm->{'column_order'};
      my $rowct = $column ? $width : $height;
      my $rowlen = $column ? $height : $width;
      my $xs = $column ? 'y' : 'x';
      my $ys = $column ? 'x' : 'y';

      my $pixels = MIME::Base64::decode_base64($bm->{'content'});
      my $offset = 0;
      for my $col (0..($rowct - 1))
      {
        for my $row (0..($rowlen - 1))
        {
          my $pi = unpack('C', substr($pixels, $offset++, 1));
          my $err = $img->SetPixel($ys => $col, $xs => $row,
                                   'channel' => 'All',
                                   'color' => $clrs[$pi]);
          die $err if $err;
        }
      }
      
      my $err = $img->Write($fname);
      die $err if $err;
    }
    
    for my $fr (@{ $coll->{'low_level_shape'} })
    {
      my $fi = $fr->{'index'};
      my $xmirror = $fr->{'x_mirror'};
      my $subf = $fr->{'window_frame'};
      
      my $bimg = $images[$fr->{'bitmap_index'}];
      next unless $bimg;
      my $img = $bimg->Clone();
      
      if ($subf)
      {
        my $simg = $images[$subf];
        next unless $simg;
        $img->Composite('image' => $simg, 'compose' => 'Over',
            'x' => $fr->{'window_left'}, 'y' => $fr->{'window_top'});
      }
      if ($xmirror)
      {
        $img->Flop();
      }
      
      $img->Write(sprintf("$tabdir/frame%03d.png", $fi));
    }
  }
}

exit;
