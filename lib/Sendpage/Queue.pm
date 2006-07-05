package Sendpage::Queue;

# this tool handles dealing with a single queue directory
# it processes *one* file at a time with a few functions
#
# $Id$
#
# Copyright (C) 2000-2004 Kees Cook
# kees@outflux.net, http://outflux.net/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# <URL:http://www.gnu.org/copyleft/gpl.html>

use 5.6.1;			# lvaluable subs
use strict;			# Avoid MetaGoof #1
use warnings;			# Avoid MetaGoof #2

use FileHandle;			# Hmmm, expensive?!?

=head1 NAME

Sendpage::Queue - implements a simple directory-based file queue

=head1 SYNOPSIS

 $queue = Sendpage::Queue->new($dir);

 while ($queue->ready()) {
     $filename = $queue->file();
     $fh       = $queue->getReadyFile();
     if ($can_remove_file) {
         $queue->fileToss();
     } else {
         $queue->fileDone();
     }
 }

 # open a new queue file
 $fh = $queue->getNewFile();
 # ... do things to the file handle here
 # release the file
 $queue->doneNewFile();

=head1 DESCRIPTION

This is a module is used internally by L<sendpage> for implementing a
simple queuing system for pages.

=cut

# globals
my $DEBUG = 0;

=head2 Methods

=over 4

=item new LIST

Instantiates a Sendpage::Queue object.

=cut

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {
		 DIR     => shift, # location of my queue
		 FILES   => [],	   # where to store our directory list
		 OPEN    => undef, # current open file
		 COUNTER => 0,	   # for the unique filename
		};

    unless (-d $self->{DIR}) {
	$main::log->do('alert',
		       "'$self->{DIR}' is not a directory!");
	return undef;
    }
    unless (-w $self->{DIR}) {
	$main::log->do('alert',
		       "Cannot write to '$self->{DIR}' directory!");
	return undef;
    }
    unless (-r $self->{DIR}) {
	$main::log->do('alert',
		       "Cannot read '$self->{DIR}' directory!");
	return undef;
    }

    return bless $self => $class;
}

=item dir EXPR

=item files LIST

=item open EXPR

=item counter EXPR

Accessor methods.

=cut

# generate accessor methods
for my $field (qw(dir files open counter)) {
    no strict "refs";
    *$field = sub : lvalue
    {
	my $self = shift;
	$self->{uc $field} = shift if @_;
	$self->{uc $field};
    };
}

=item file()

Emit the first file in the queue.

=cut

sub file
{
    my $self = shift;
    return ${$self->files}[0];
}

=item ready()

Check if a Queue is ready.

=cut

# is the queue ready to have files taken from it?
sub ready
{
    my $self = shift;

    if ($self->open) {
	$main::log->do('alert',
		       "File '${$self->files}[0]' still open "
		       . "while checking queue '$self->dir'"
		       . " -- restarting queue!");
	#return -2;
    }

    opendir DIRHANDLE, $self->dir
	or $main::log->do('alert', "Cannot access '$self->dir': $!");
    my @files = readdir DIRHANDLE;
    close DIRHANDLE;

    map { warn "$$: in '$self->dir': $_\n" } @files if $DEBUG;

    $self->files = [ grep /^q/, @files ];
    @files = @{ $self->files };

    map { warn "$$: in FILES: $_\n" } @files if $DEBUG;
    warn "$$: ready will be: $#files\n"      if $DEBUG;

    return $#files;
}

=item getReadyFile()

Get a file handle from the queue.

=cut

# get a file handle from the queue
#	handle is locked, and must be release with "fileDone"
sub getReadyFile
{
    my $self = shift;
    my $fh = new FileHandle;

    if ($self->open) {
	$main::log->do('alert',
		       "Cannot read next file from queue '$self->dir'"
		       . " with open file (${$self->files}[0])!");

	return undef;
    }
    warn "$$: in getReadyFile\n" if $DEBUG;
    my @filelist = @{ $self->files };
    my $file     = shift @filelist;
    unless (defined $file) {
	warn "$$: no more files in queue\n" if $DEBUG;
	$main::log->do('debug', "No more files in queue")
	    if $main::DEBUG;
	return undef;
    }

    my $err   = "queue '$file' from '$self->dir':";
    my $fname = "$self->dir/$file";

    warn "$$: fname is '$fname'\n" if $DEBUG;

    # create new queue files
    unless (-f $fname) {
	warn "$$: creating '$fname'\n" if $DEBUG;
	open $fh, "> $fname"
	    or $main::log->do('alert', "Cannot write $err $!");
	close $fh;
    }

    # open queue files read/write
    unless (open $fh, "+< $fname") {
	warn "$$: cannot read $err $!\n" if $DEBUG;
	$main::log->do('alert', "Cannot read $err $!");

	# try the next file
	shift @{ $self->files };
	return $self->getReadyFile();
    }

    unless ($self->lockFile($fname)) {
	warn "$$: cannot lock $err $!\n" if $DEBUG;
	$main::log->do('alert', "Cannot lock $err $!");
	close $fh;

	# try the next file
	shift @{ $self->files };
	return $self->getReadyFile();
    }

    unless (-f $fname) {
	warn "$$: cannot find '$fname'\n" if $DEBUG;
	# someone deleted the file while they had it locked,
	close $fh;

	# we should try for the next file in the queue
	shift @{ $self->files };
	return $self->getReadyFile();
    }

    warn "$$: file handle is '$fh'\n" if $DEBUG;
    $self->open = $fh;

    return $self->open;
}

=item fileToss LIST

Releases locks, closes file, removes file, etc...

=cut

# releases locks, closes file, removes file, etc
sub fileToss
{
    my ($self, @args) = @_;

    unless ($self->open) {
	$main::log->do('alert', "Cannot call fileToss without an open file!");
	return undef;
    }

    # rename before unlock: no one can get it then FIXME: this is not right
    my $fname = "$self->dir/${$self->files}[0]";

    #	my $newname=$fname;
    #	$newname =~ s/^./X/;
    #
    #	# need the queue dirs here, too
    #	$fname=$self->{DIR}."/$fname";
    #	$final=$self->{DIR}."/$newname";
    #	if (!rename($fname,$final)) {
    #		$main::log->do('crit', "Cannot rename '$fname' -> '$final': $!\n");
    #	}

    if (unlink($fname) < 1) {
	$main::log->do('alert',
		       "Could not delete file '$fname': $!");
    }

    $self->unlockFile($fname);
    close $self->open;
    $self->open = undef;

    # drop the filename
    shift @{ $self->files };

    return 1;
}

=item fileDone()

Releases locks, closes file, assumes that it should stay...

=cut

# releases locks, closes file, assumes that it should stay
sub fileDone
{
    my $self = shift;

    unless ($self->open) {
	$main::log->do('alert',
		       "Cannot call fileDone without an open file!");
	return undef;
    }

    my $fname = "$self->dir/${$self->files}[0]";

    $self->unlockFile($fname);
    close $self->open;
    $self->open = undef;
    shift @{ $self->files };	# drop the leading filename

    return 1;
}

=item getNewFile()

Gets a new file handle, must be released with "doneNewFile".

=cut

# gets a new file handle, must be released with "doneNewFile"
sub getNewFile
{
    my $self = shift;

    if ($self->open) {
	$main::log->do('alert',
		       "Cannot create new file for queue '$self->dir'"
		       . " with open file (${$self->files}[0])!");
	return undef;
    }

    # createUniqueName only works sanely if we don't re-instantiate
    # the same PagingQueue multiple times within the same process within
    # the same second.  (Since the COUNTER would be reset to zero each
    # time)  :(  As a result, we must test for pre-existing queue filenames.
    my $name;
    do {
	$name = $self->createUniqueName();
    } while (-f $self->dir . "/q" . $name);
    unshift @{ $self->files }, "Q" . $name;
    return $self->getReadyFile();
}

=item doneNewFile()

FIXME

=cut

sub doneNewFile
{
    my $self = shift;

    my ($fname, $final);

    unless (defined $self->open) {
	$main::log->do('alert',
		       "Cannot close new file while no file is open!");
	return undef;
    }

    $fname = ${$self->files}[0];
    if ($fname !~ /^Q/) {
	$main::log->do('alert', "Not operating on a new Queue file");
	return undef;
    }

    my $newname = $fname;
    $newname =~ s/^Q/q/;

    # need the queue dirs here, too
    $fname = "$self->dir/$fname";
    $final = "$self->dir/$newname";
    unless (rename($fname, $final)) {
	$main::log->do('crit', "Cannot rename '$fname' -> '$final': $!\n");
    }

    # done with this handle
    if ($self->fileDone()) {
	return $newname;
    }
    return undef;
}

=for developers: add new functions here.

=back

=cut


#############
# internal functions
#############

# locks a single file  FIXME
sub lockFile
{
    my ($self, $file) = @_;
    $main::log->do('debug', "need to be locking '$file'")
	if $main::DEBUG;
    return 1;
}

# unlocks a single file   FIXME
sub unlockFile
{
    my ($self, $file) = @_;
    $main::log->do('debug', "need to be unlocking '$file'")
	if $main::DEBUG;
    return 1;
}

# locks the queue run (do we really need this?)
sub lockQueue
{
    # Do something to lock the queue
}

# unlocks the queue directory (may not need this...)
sub unlockQueue
{
    # Do something to unlock the queue
}

# returns a name based on time, process id, hostname, and cycle
# FIXME: USE the hostname
# FIXME: if you re-instantiate the same queue within the same
#        second, within the same process, this will NOT produce
#        a unique name!  Argh.
sub createUniqueName
{
    my $self = shift;
    $self->counter += 1;	# a bit contrived since we're using an
				# lvalued counter

    return sprintf("%010d%05d%03d",
		   time(), $$, $self->counter);
}

1;				# This is a module

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 BUGS

Need to write more docs.

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::KeesLog>,
L<Sendpage::Modem>, L<Sendpage::PagingCentral>, L<Sendpage::PageQueue>,
L<Sendpage::Page>, L<Sendpage::Recipient>

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
