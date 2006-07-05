package Sendpage::PageQueue;

# this module uses the Queue module, but plays with Pages on top of it
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

use strict;
use warnings;

our @ISA = ("Sendpage::Queue");

# we're extending the Queue module, which is only file based, and in
# the hopes that we can attach this to a better Queue module if one
# ever surfaces on CPAN
use Sendpage::Queue;

# other stuff
use Sendpage::Page;
use Sendpage::Recipient;

=head1 NAME

Sendpage::PageQueue - extends the Queue module, adding the Page module smarts

=head1 SYNOPSIS

 $pqueue = Sendpage::PageQueue($config);

 # read waiting pages
 while ($fh = $pqueue->getPage($db)) {
     # build up $page
     @stuff = $pqueue->pullPageFromFile($db, $fh);
     $page = Sendpage::Page->new(@stuff);

     # do something to change $page

     # write changes back to queue
     $pqueue->writePage($page);

     $pqueue->fileDone();
 }

 # add a new page
 $fh = $pqueue->addPage($page);

=head1 DESCRIPTION

This module is used internally by L<sendpage> for is page processing.

=cut

sub new
{
    # get our args
    my $proto  = shift;
    my $config = shift;		# we'll need the config info
    my $class  = ref($proto) || $proto;
    my $self   = $class->SUPER::new(@_);

    $self->{CONFIG} = $config;

    return bless $self => $class;
}

sub getPage
{
    my $self = shift;
    my $db   = shift;

    my $handle = $self->getReadyFile();

    if (defined $handle) {
	# read the data
	my $page = new Sendpage::Page
	    $self->pullPageFromFile($db, $handle);

	$page->option('FILE', $self->file()) if $page;
	return $page;
    } else {
	return undef;
    }
}

sub pullPageFromFile
{
    my $self = shift;
    my $db   = shift;
    my $fh   = shift;

    my($line, $body, @lines, @recips, $text, %options, $recip);

    # rewind our file
    seek $fh, 0, 0;

    # load everything
    @lines = <$fh>;

    # clear everything!
    $body = 0;
    undef @recips;
    undef %options;
    undef $text;

    foreach $line (@lines) {
	chomp $line;

	#print STDERR "read line '$line' ";
	if ($body == 1) {
	    #warn "(body)\n";
	    $text .= $line . "\n";
	} else {
	    if ($line =~ /^\s*$/) {
		# header/body break
		$body=1;
		#warn "\n";
	    } else {
		my ($key, $value) = split(/:\s*/, $line, 2);

		#warn "(header: '$key' -> '$value')\n";

		if ($key eq "to") {
		    my(@parts, %data, $key, $line, $datum);
		    undef %data;
		    @parts = split /,/ => $value;
		    $value = shift @parts;
		    foreach $line (@parts) {
			($key, $datum) = split(/=/, $line, 2);
			$data{$key} = $datum;
		    }

		    $recip = new Sendpage::Recipient
			$self->{CONFIG}, $db, $value, \%data;
		    if (defined $recip) {
			push @recips, $recip;
		    } else {
			$main::log->do('warning',
				       "bad recip: '%s'",$value);
		    }
		} else {
		    $options{$key} = $value;
		}
	    }
	}
    }

    # rewind our file
    seek $fh, 0, 0;

    # drop last CR .... FIXME: is this right?  Hm.
    chomp $text;

    return (\@recips, \$text, \%options);
}

sub addPage
{
    my ($self, $page) = @_;

    my($rc, $filename);
    my $handle = $self->getNewFile();

    return undef unless defined $handle;

    $page->option("queued", time);
    $rc = $self->writePage($page);
    $filename = $self->doneNewFile();
    return $filename if $rc;
    return $rc;
}

sub writePage
{
    my ($self, $page) = @_;

    my $handle = $self->{OPEN};

    return undef unless defined $handle;

    # clear this file, just in case
    seek $handle, 0, 0;
    truncate $handle, 0;

    print $handle $page->dump();

    return 1;
}

1;				# This is a module

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 BUGS

Obviously, needs more docs.

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::KeesLog>,
L<Sendpage::Modem>, L<Sendpage::PagingCentral>, L<Sendpage::Page>,
L<Sendpage::Recipient>, L<Sendpage::Queue>.

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
