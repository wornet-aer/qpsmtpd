# $Id: Client.pm,v 1.8 2005/02/14 22:06:38 msergeant Exp $

package Danga::Client;
use base 'Danga::TimeoutSocket';
use fields qw(line closing disable_read can_read_mode);
use Time::HiRes ();

# 30 seconds max timeout!
sub max_idle_time { 30 }

sub new {
    my Danga::Client $self = shift;
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new( @_ );

    $self->reset_for_next_message;
    return $self;
}

sub reset_for_next_message {
    my Danga::Client $self = shift;
    $self->{line} = '';
    $self->{disable_read} = 0;
    $self->{can_read_mode} = 0;
    return $self;
}

sub get_line {
    my Danga::Client $self = shift;
    if (!$self->have_line) {
        $self->SetPostLoopCallback(sub { $self->have_line ? 0 : 1 });
        #warn("get_line PRE\n");
        $self->EventLoop();
        #warn("get_line POST\n");
        $self->watch_read(0);
    }
    return if $self->{closing};
    # now have a line.
    $self->{alive_time} = time;
    $self->{line} =~ s/^(.*?\n)//;
    return $1;
}

sub can_read {
    my Danga::Client $self = shift;
    my ($timeout) = @_;
    my $end = Time::HiRes::time() + $timeout;
    warn("Calling can-read\n");
    $self->{can_read_mode} = 1;
    if (!length($self->{line})) {
        my $old = $self->watch_read();
        $self->watch_read(1);
        $self->SetPostLoopCallback(sub { (length($self->{line}) || 
                                         (Time::HiRes::time > $end)) ? 0 : 1 });
        #warn("get_line PRE\n");
        $self->EventLoop();
        #warn("get_line POST\n");
        $self->watch_read($old);
    }
    $self->{can_read_mode} = 0;
    $self->SetPostLoopCallback(sub { $self->have_line ? 0 : 1 });
    return if $self->{closing};
    $self->{alive_time} = time;
    warn("can_read returning for '$self->{line}'\n");
    return 1 if length($self->{line});
    return;
}

sub have_line {
    my Danga::Client $self = shift;
    return 1 if $self->{closing};
    if ($self->{line} =~ /\n/) {
        return 1;
    }
    return 0;
}

sub event_read {
    my Danga::Client $self = shift;
    my $bref = $self->read(8192);
    return $self->close($!) unless defined $bref;
    # $self->watch_read(0);
    $self->process_read_buf($bref);
}

sub process_read_buf {
    my Danga::Client $self = shift;
    my $bref = shift;
    $self->{line} .= $$bref;
    return if $self->{can_read_mode};
    return if $::LineMode;
    
    while ($self->{line} =~ s/^(.*?\n)//) {
        my $line = $1;
        $self->{alive_time} = time;
        my $resp = $self->process_line($line);
        if ($::DEBUG > 1 and $resp) { print "$$:".($self+0)."S: $_\n" for split(/\n/, $resp) }
        $self->write($resp) if $resp;
        $self->watch_read(0) if $self->{disable_read};
    }
}

sub disable_read {
    my Danga::Client $self = shift;
    $self->{disable_read}++;
    $self->watch_read(0);
}

sub enable_read {
    my Danga::Client $self = shift;
    $self->{disable_read}--;
    if ($self->{disable_read} <= 0) {
        $self->{disable_read} = 0;
        $self->watch_read(1);
    }
}

sub process_line {
    my Danga::Client $self = shift;
    return '';
}

sub close {
    my Danga::Client $self = shift;
    $self->{closing} = 1;
    print "closing @_\n" if $::DEBUG;
    $self->SUPER::close(@_);
}

sub event_err { my Danga::Client $self = shift; $self->close("Error") }
sub event_hup { my Danga::Client $self = shift; $self->close("Disconnect (HUP)") }

1;
