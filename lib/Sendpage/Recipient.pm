#
# this package will encapsulate the data of a single recipient
#
# $Id$
#
# Copyright (C) 2000,2001 Kees Cook
# cook@cpoint.net, http://outflux.net/
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

package Sendpage::Recipient;

=head1 NAME

Recipient.pm - encapsulates the data of a single recipient

=head1 SYNOPSIS

    $recip=Sendpage::Recipient->new($config,$name,$data);
    $alias=$recip->alias();
    @dests=@{ $recip->dests() };
    @data=@{ $recip->data() };
    $value=$recip->datum("field");
    $pin=$recip->pin();
    $pc=$recip->pc();
    $name=$recip->name();

=head1 DESCRIPTION

This is a module for use in sendpage(1).

=head1 BUGS

Need to write more docs.

=cut


sub new {
	# spec for data mapping
	my @RecipSpec = (
		"email-cc"
	);
		
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};

	$self->{CONFIG}= shift;		# configuration
	my $name = shift;		# our look-up name
	my $data = shift;		# ref to hash of misc info
	my @list;

	# who are all our destinations?
	my $list  = $self->{CONFIG}->get("recip:${name}\@dest",1);
	if (!defined($list) && $name !~ /\@/) {
		$main::log->do('debug',"No such recipient: '$name'")
			if ($self->{CONFIG}->get("alias-debug"));
		return undef;
	}
	else {
		@list=@{ $list };
	}

	#warn "DESTS:\n";
	#my $cow;
	#foreach $cow (@list) {
	#	warn "dest: $cow\n";
	#}
	#warn "--end-($#list)\n";

	# do we exist at all?
	if (!defined($list) || $#list < 0) {
		# if we don't exist as a valid "alias" with options,
		# then we should allow expansion if we contain "@",
		# and a valid PC identifier

		if ($name =~ /\@/) {
			my @parts;
			@parts=split(/\@/,$name,2);

			$self->{PIN}=$parts[0];
			$self->{PC}=$parts[1];
			# verify that we have a legit PC
			if (!$self->{CONFIG}->instance_exists("pc:".$self->{PC})) {
				$main::log->do('warning',
					"no such PC '$self->{PC}' defined for '$self->{PIN}'!");
				return undef;
			}
			# build up the destination "list"
			undef @list;
			push(@list, $name );
			$list=\@list;
		}
		else {
			return undef;
		}
	}
	# are we a single entity, that isn't an alias?
	elsif ($#list == 0 &&
	       ($list[0]=~ /\@/ || 
	       !$self->{CONFIG}->instance_exists("recip:".$list[0]))) {

		# we are at the end of the line
		$self->{ALIAS}=0;

		my @parts;
		@parts=split(/\@/,$list[0],2);

		$self->{PIN}=$parts[0];
		$self->{PC}=$parts[1];
		# verify that we have a legit PC
		if (!$self->{CONFIG}->instance_exists("pc:".$self->{PC})) {
			$main::log->do('warning',
				"no such PC '$self->{PC}' defined for '$self->{PIN}'!");
			return undef;
		}
	}
	else {
		$self->{ALIAS}=1;
	}
	$self->{DEST} = $list;
	$self->{DATA} = ();

	my $thing;
	# handle passing generics down to recipient
	foreach $thing (@RecipSpec) {
		# FIXME: clean this up
		my($generic,$datum);
		undef $generic;
		# first, get generic from passed in variables
		$generic=$data->{$thing} if
			defined($data->{$thing});
		# next, get from specific recip entry if it exists
		$datum=$self->{CONFIG}->get("recip:${name}\@${thing}",1);
		if (defined($datum) || defined($generic)) {
			$self->{DATA}->{$thing}=
				defined($datum) ? $datum : $generic;
			#printf "datum '%s' is '%s'\n",
			#	$thing,
			#	$self->{DATA}->{$thing};
		}
	}

	$self->{NAME} = $name;

	#warn "Recipient '$name' built\n";

        bless($self,$class);
        return $self;
}

sub alias {
	my($self)=shift;
	
	$self->{ALIAS};
}

sub dests {
	my($self)=shift;

	$self->{DEST};
}

sub data {
	my($self)=shift;

	$self->{DATA};
}

sub datum {
	my($self,$want)=@_;

	$self->{DATA}->{$want};
}

sub pin {
	my($self)=shift;

	$self->{PIN};
}

sub pc {
	my($self)=shift;

	$self->{PC};
}

sub name {
	my($self)=shift;

	$self->{NAME};
}

1;

__END__

=head1 AUTHOR

Kees Cook <cook@cpoint.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3),
Sendpage::Modem(3), Sendpage::PagingCentral(3), Sendpage::PageQueue(3),
Sendpage::Page(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

