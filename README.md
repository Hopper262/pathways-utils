pathways-utils
==============

Perl scripts to read and write Pathways Into Darkness data files. These generally use XML as an intermediate format, to easily inspect the binary data and to separate file parsing from transformation tasks.

These are all command-line tools. Usually the input is expected on stdin and output is written to stdout.

### pidshapes2xml.pl

Converts a PiD Shapes file (or more properly, the resource fork) into an XML file compatible with the scripts in marathon-utils. There are a few attributes unique to Pathways that are ignored by the Marathon tools.

### pidshapesxml2images.pl

Takes XML output from the above, and builds a directory of images in PNG format. Handles Pathways' variant textures, made by combining two bitmaps from the Shapes file.

### save2dpin.pl

This extracts a single slot from a Pathways save file, and exports it in the same format as PiD's built-in "new game" data. That data lives in the application's "dpin" resource, hence the name.

### dpin2xml.pl

This reads "dpin" data from the app or above script, and exports an XML file of all the known variables. The Pathways "A1" demo had a different layout, and this script handles both formats with a command-line switch. Some parts of the data remain unidentified; as with Marathon, the data is mostly a dump of native data structures, and some holes may be garbage or in-memory data not imported from the save.

### pidmap2xml.pl

Converts the PiD Maps file into an XML file for inspection or further processing. Requires the "io.subs" helper library.

### pidmapxml2images.pl

Takes XML output from the above, and builds maps similar to what you'd see in-game. It needs the Shapes images to be generated, as those contain the individual map squares. Note that many of these show inaccessible areas, so the generated maps are different than you'd ever actually see in the game.

### pidmapxml2obj.pl, create_pidmtl.pl, level2obj.pl

Takes XML output from the map script, and builds Wavefront .OBJ files suitable for isometric-style viewing. (The ceilings cover the empty space, not the rooms.) The "level2obj.pl" variant includes scenery and monsters; adjust the angle on line 245 to match your desired view.



