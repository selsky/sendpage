#
# this package will encapsulated the data of an actual page to be
# send, including all the recipients.
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html

package Sendpage::Page;

=head1 NAME

Sendpage::Page - encapsulates the data of an actual page

=head1 SYNOPSIS

This module gets used in sendpage(1).

=head1 DESCRIPTION

    $page=Sendpage::Page->new(\@recipients, \$text, \%options);

    $data=$page->dump();	# storable dump of page data

    if ($page->deliverable()) {
	for ($page->reset(), $page->next();
	     $recip=$page->recip();
	     $page->next()) {
		$text=$page->text();	# get text of page
		$page->drop_recip();	# discard current recipient
	}
	$page->attempts(1);
    }
    $anyone_left=$page->has_recips();
    $attempts=$page->attempts();
    $age=$page->age();

    $page->option('from',"someone else"); # set option named 'from'
    $from=$page->option('from');	  # get option named 'from'

    $page->option('from',$from,1); # delete option named 'from'


=head1 BUGS

This needs more docs.

=cut


sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};

	my $o=$_[0]; my $w=$_[1]; my $t=$_[2];
	#warn "Page: 1: $o 2: $w 3: $t\n";

	$self->{RECIPS}=$o;		# deref the recipients reference list
	$self->{TEXT}=${ $w };		# text of the page
	$self->{DATA}=$t;		# hash of delivery options

	# dump what we just loaded
	#warn "loading page with:\n\ttext: '".$self->{TEXT}."'\n";
	#foreach $key (sort keys %{ $self->{DATA} }) {
	#	warn "\toption: $key -> ".$self->{DATA}->{$key}."\n";	
	#}
	#foreach $recip (@{$self->{RECIPS}}) {
	#	warn "\trecip: $recip\n";	
	#}

	# our "internal" counters
	$self->{DATA}->{'attempts'}+=0;
	$self->{ACTIVE}=undef;	# which recipient is active (array loop)

        bless($self,$class);
        return $self;
}

# return the text
sub text {
	my($self)=shift;

	return $self->{TEXT};
}

# we need a way to loop through all the recipients.
# I think I'm going to borrow from the PHP-style of array stepping
sub reset {
	my($self)=shift;

	$self->{ACTIVE}=-1;
}

# which recip is up next?
sub next {
	my($self)=shift;

	$self->{ACTIVE}+=1;
}

# show a recipient
sub recip {
	my($self)=shift;

	#warn "returning RECIP: ".$self->{ACTIVE}."\n";
	
	return $self->{RECIPS}->[$self->{ACTIVE}];
}

# do we have any recips left?
sub has_recips {
	my($self)=shift;

	return defined($self->{RECIPS}->[0]);
}

# drop a recipient (total failure or success)
sub drop_recip {
	my($self)=shift;

	splice(@{ $self->{RECIPS} }, $self->{ACTIVE}, 1);

	# need to drop the ACTIVE counter, don't I, so the next "next"
	# will work...
	$self->{ACTIVE}--;
}

# is the page deliverable?
sub deliverable {
	my($self)=shift;

	# right now, we can support the "when to schedule" option,
	# but in theory, we should be able to extend this to anything
	# else we can think of.
	return 1 if (time >= $self->{DATA}->{'when'});
	return undef;
}

sub age {
    my($self)=shift;

    return (time - $self->{DATA}->{'queued'});
}

sub option {
	my($self,$opt,$value,$delete)=@_;

	if (defined($value)) {
		if (defined($delete) && $value eq $self->{DATA}->{$opt}) {
			delete $self->{DATA}->{$opt};
		}
		else {	
			$self->{DATA}->{$opt}=$value;
		}
	}
	$self->{DATA}->{$opt};
}

sub attempts {
	my($self,$inc)=@_;

	$inc=0 if (!defined($inc));

	$self->{DATA}->{'attempts'}+=$inc;
}

sub dump {
	my($self)=@_;

	my($str,$recip,$key);

	$str="";

        for ($self->reset(), $self->next();
             defined($recip=$self->recip());
             $self->next()) {
		my(@list);
		undef @list;
		push(@list,$recip->name());
		if (defined($recip->data())) {
			foreach $key (keys %{ $recip->data() }) {
				push(@list,"${key}=".$recip->datum($key));
			}
		}
                $str.="to: ".join(",",@list)."\n";
        }
        foreach $key (sort keys %{ $self->{DATA} }) {
                $str.="$key: ".$self->{DATA}->{$key}."\n";
        }
	$str.="\n".$self->{TEXT}."\n";

	return $str;
}

1;

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3),
Sendpage::Modem(3), Sendpage::PagingCentral(3), Sendpage::PageQueue(3), 
Sendpage::Recipient(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
