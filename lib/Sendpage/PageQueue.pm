#
# this module uses the Queue module, but plays with Pages on top of it
#
# $Id$
#
# Copyright (C) 2000 Cornelius Cook
# cook@cpoint.net, http://collective.cpoint.net/
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html

package Sendpage::PageQueue;
# we're extending the Queue module, which is only file based, and in
# the hopes that we can attach this to a better Queue module if one
# ever surfaces on CPAN
use Sendpage::Queue;
use strict;
use vars qw(@ISA);
@ISA = ("Sendpage::Queue");

# other stuff
use Sendpage::Page;
use Sendpage::Recipient;

=head1 NAME

PageQueue.pm - extends the Queue module, adding the Page module smarts

=head1 SYNOPSIS

    $pqueue=Sendpage::PageQueue($config);

    # read waiting pages
    while ($fh=$pqueue->getPage()) {
	# build up $page
	@stuff=$pqueue->pullPageFromFile($fh);
	$page=Sendpage::Page->new(@stuff);

	# do something to change $page

	# write changes back to queue
	$pqueue->writePage($page);

	$pqueue->fileDone();
    }

    # add a new page
    $fh=$pqueue->addPage($page);

=head1 DESCRIPTION

This is a module for use in sendpage(1).

=head1 BUGS

Obviously, needs more docs.

=cut


sub new {
        # get our args
        my $proto = shift;
	my $config = shift;	# we'll need the config info
        my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new(@_);

	$self->{CONFIG}=$config;

        bless($self, $class);
        return $self;
}

sub getPage {
	my $self = shift;

	my $handle = $self->getReadyFile();

	if (defined($handle)) {
		# read the data
		my $page=Sendpage::Page->new($self->pullPageFromFile($handle));

		return $page;
	}
	else {
		return undef;
	}
}

sub pullPageFromFile {
	my $self=shift;
	my $fh  =shift;

	my($line,$body,@lines,@recips,$text,%options,$recip);

	# rewind our file
	seek $fh, 0, 0;

	# load everything
	@lines=<$fh>;

	# clear everything!
	$body=0;
	undef @recips;
	undef %options;
	undef $text;

	foreach $line (@lines) {
		chomp($line);

		#print STDERR "read line '$line' ";
		if ($body == 1) {
			#warn "(body)\n";
			$text.=$line."\n";
		}
		else {
			if ($line =~ /^\s*$/) {
				# header/body break
				$body=1;	
				#warn "\n";
			}
			else {
				my($key, $value);
				($key,$value)=split(/:\s*/,$line,2);

				#warn "(header: '$key' -> '$value')\n";

				if ($key eq "to") {
					my(@parts,%data,$key,$line,$datum);
					undef %data;
					@parts=split(/,/,$value);
					$value=shift @parts;
					foreach $line (@parts) {
						($key,$datum)=split(/=/,$line,2);
						$data{$key}=$datum;
					}

					
					if (defined($recip=Sendpage::Recipient->new($self->{CONFIG},$value,\%data))) {
						push(@recips,$recip);
					}
					else {
						$main::log->do('warning',
							"bad recip: '$value'");
					}
				}
				else {
					$options{$key}=$value;
				}
			}
		}
	}

	# rewind our file
	seek $fh, 0, 0;

	# drop last CR .... FIXME: is this right?  Hm.
	chomp($text);

	return (\@recips, \$text, \%options);
}

sub addPage {
	my ($self,$page) = @_;

	my $rc;
	my $handle = $self->getNewFile();

	if (!defined($handle)) {
		return undef;
	}

	$rc=$self->writePage($page);
	$self->doneNewFile();
	return $rc;
}

sub writePage {
	my($self,$page)=@_;

	my $handle = $self->{OPEN};

	return undef if (!defined($handle));

	# clear this file, just in case
	seek $handle, 0, 0;
	truncate $handle, 0;

	print $handle $page->dump();

	return 1;
}

1;

__END__

=head1 AUTHOR

Kees Cook <cook@cpoint.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3),
Sendpage::Modem(3), Sendpage::PagingCentral(3), Sendpage::Page(3),
Sendpage::Recipient(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

