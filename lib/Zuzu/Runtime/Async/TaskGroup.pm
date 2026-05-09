package Zuzu::Runtime::Async::TaskGroup;

use utf8;

our $VERSION = '0.001';

use Moo;
use Scalar::Util qw( refaddr weaken );

has 'parent' => ( is => 'rw' );
has 'tasks' => ( is => 'rw', default => sub { {} } );
has 'cancelled' => ( is => 'rw', default => sub { 0 } );
has 'reason' => ( is => 'rw' );

sub BUILD {
	my ( $self ) = @_;

	weaken( $self->{parent} ) if defined $self->{parent};
}

sub add {
	my ( $self, $task ) = @_;

	return $task if !defined $task;
	$self->tasks->{ refaddr($task) } = $task;
	$task->group($self) if $task->can('group');

	return $task;
}

sub remove {
	my ( $self, $task ) = @_;

	return if !defined $task;
	delete $self->tasks->{ refaddr($task) };

	return;
}

sub cancel {
	my ( $self, $reason ) = @_;

	$self->cancelled(1);
	$self->reason($reason) if defined $reason;
	for my $task ( values %{ $self->tasks } ) {
		$task->cancel($reason) if $task->can('cancel');
	}

	return $self;
}

1;
