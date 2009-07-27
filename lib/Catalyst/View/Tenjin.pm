package Catalyst::View::Tenjin;

use strict;
use base qw/Catalyst::View/;
use Data::Dump 'dump';
use Tenjin;
use MRO::Compat;

our $VERSION = '0.01';

sub _coerce_paths {
	my ($paths, $dlim) = shift;
	return () if ( !$paths );
	return @{$paths} if ( ref $paths eq 'ARRAY' );

	# tweak delim to ignore C:/
	unless ( defined $dlim ) {
		$dlim = ( $^O eq 'MSWin32' ) ? ':(?!\\/)' : ':';
	}
	return split( /$dlim/, $paths );
}

sub new {
	my ( $class, $c, $arguments ) = @_;
	my $config = {
		EVAL_PERL          => 0,
		TEMPLATE_EXTENSION => '',
		%{ $class->config },
		%{$arguments},
	};
	if ( ! (ref $config->{INCLUDE_PATH} eq 'ARRAY') ) {
		my $delim = $config->{DELIMITER};
		my @include_path = _coerce_paths( $config->{INCLUDE_PATH}, $delim );
		if ( !@include_path ) {
			my $root = $c->config->{root};
			my $base = Path::Class::dir( $root, 'base' );
			@include_path = ( "$root", "$base" );
		}
		$config->{INCLUDE_PATH} = \@include_path;
	}

	if ( $c->debug && $config->{DUMP_CONFIG} ) {
		$c->log->debug( "Tenjin Config: ", dump($config) );
	}

	my $self = $class->next::method(
		$c, { %$config }, 
	);
	
	#$self->config($config);

	if ($config->{USE_STRICT}) {
		$Tenjin::USE_STRICT = 1;
	}
	
	$self->{template} = Tenjin::Engine->new({ path => $config->{INCLUDE_PATH} });

	return $self;
}

sub process {
	my ($self, $c) = @_;

	my $template = $c->stash->{template} || $c->action . $self->config->{TEMPLATE_EXTENSION};

	unless (defined $template) {
		$c->log->debug('No template specified for rendering') if $c->debug;
		return 0;
	}

	my $output = $self->render($c, $template);

	unless ($c->response->content_type) {
		$c->response->content_type('text/html; charset=utf-8');
	}

	$c->response->body($output);

	return 1;
}

sub check_tmpl {
	my ($self, $name) = @_;

	return exists $self->{template}->{templates}->{$name} ? 1 : undef;
}

sub register {
	my ($self, $tmpl_name, $tmpl_content) = @_;

	my $template = Tenjin::Template->new(undef, $self->{template}->{init_opts_for_template});
	$template->{timestamp} = time();
	$template->convert($tmpl_content);
	$template->compile();

	$self->{template}->register_template($tmpl_name, $template);
}

sub render {
	my ($self, $c, $tmpl_name, $args) = @_;

	$c->log->debug(qq/Rendering template "$tmpl_name"/) if $c->debug;

	my $vars = {
		(ref $args eq 'HASH' ? %$args : %{ $c->stash() }),
		$self->template_vars($c)
	};

	local $self->{include_path} = 
		[ @{ $vars->{additional_template_paths} }, @{ $self->{include_path} } ]
		if ref $vars->{additional_template_paths};

	return $self->{template}->render($tmpl_name, $vars);
}

sub template_vars {
	my ($self, $c) = @_;

	my $cvar = $self->config->{CATALYST_VAR};

	defined $cvar
	? ( $cvar => $c )
	: (
		c    => $c,
		base => $c->req->base,
		name => $c->config->{name}
	)
}

__PACKAGE__;

__END__

=pod

=head1 NAME

Catalyst::View::Tenjin - Tenjin view class for Catalyst.

=head1 SYNOPSIS

	# create your view
	package MyApp::View::Tenjin;

	use strict;
	use base 'Catalyst::View::Tenjin';

	# set configuration, here or in your app's config file,
	# if you don't want to use strict you don't have to.
	__PACKAGE__->config(
		USE_STRICT => 1,
		INCLUDE_PATH => [ MyApp->path_to('root', 'templates') ],
		TEMPLATE_EXTENSION => '.html',
	);

	1;
         
	# render view from lib/MyApp.pm or lib/MyApp::C::SomeController.pm

	sub message : Global {
		my ($self, $c) = @_;

		$c->stash->{template} = 'message.html';
		$c->stash->{message}  = 'Hello World!';
		$c->forward('MyApp::View::Tenjin');
	}

	# access variables from template

    The message is: [== $message =].
    
    # example when CATALYST_VAR is set to 'Catalyst'
    Context is [== $Catalyst =]          
    The base is [== $Catalyst->req->base =] 
    The name is [== $Catalyst->config->name =] 
    
    # example when CATALYST_VAR isn't set
    Context is [== $c =]
    The base is [== $base =]
    The name is [== $name =]

	# you can also embed Perl
	<?pl if ($c->action->namespace eq 'admin') { ?>
		<h1>admin is not implemented yet</h1>
	<?pl } ?>

=cut

=head1 DESCRIPTION

This is the Catalyst view class for the L<Tenjin>.
Your application should defined a view class which is a subclass of
this module. There is no helper script to create this class automatically,
but you can do so easily as described in the synopsis.

Now you can modify your action handlers in the main application and/or
controllers to forward to your view class. You might choose to do this
in the end() method, for example, to automatically forward all actions
to the Tenjin view class.

    # In MyApp or MyApp::Controller::SomeController
    
    sub end : Private {
        my( $self, $c ) = @_;
        $c->forward('MyApp::View::Tenjin');
    }

=head2 CONFIGURATION

To configure your view class, you can call the C<config()> method
in the view subclass. This happens when the module is first loaded.

    package MyApp::View::Tenjin;
    
    use strict;
    use base 'Catalyst::View::Tenjin';

    __PACKAGE__->config(
		USE_STRICT => 1,
		INCLUDE_PATH => [ MyApp->path_to('root', 'templates') ],
		TEMPLATE_EXTENSION => '.html',
	);
 
You can also define a class item in your main application configuration,
again by calling the uniquitous C<config()> method. The items in the class
hash are added to those already defined by the above two methods. This
happens in the base class new() method (which is one reason why you must
remember to call it via C<MRO::Compat> if you redefine the C<new()> 
method in a subclass).

    package MyApp;
    
    use strict;
    use Catalyst;
    
    MyApp->config({
        name     => 'MyApp',
        root     => MyApp->path_to('root'),
        'View::Tenjin' => {
			USE_STRICT => 1,
			INCLUDE_PATH => [ MyApp->path_to('root', 'templates') ],
			TEMPLATE_EXTENSION => '.html',
        },
    });

=head2 DYNAMIC INCLUDE_PATH

Sometimes it is desirable to modify INCLUDE_PATH for your templates at run time.
 
Additional paths can be added to the start of INCLUDE_PATH via the stash as
follows:

    $c->stash->{additional_template_paths} =
        [$c->config->{root} . '/test_include_path'];

If you need to add paths to the end of INCLUDE_PATH, there is also an
include_path() accessor available:

    push( @{ $c->view('Tenjin')->include_path }, qw/path/ );

Note that if you use include_path() to add extra paths to INCLUDE_PATH, you
MUST check for duplicate paths. Without such checking, the above code will add
"path" to INCLUDE_PATH at every request, causing a memory leak.

A safer approach is to use include_path() to overwrite the array of paths
rather than adding to it. This eliminates both the need to perform duplicate
checking and the chance of a memory leak:

    @{ $c->view('Tenjin')->include_path } = qw/path another_path/;

If you are calling C<render> directly then you can specify dynamic paths by 
having a C<additional_template_paths> key with a value of additonal directories
to search. See L<CAPTURING TEMPLATE OUTPUT> for an example showing this.

=head2 RENDERING VIEWS

The view plugin renders the template specified in the C<template>
item in the stash.  

    sub message : Global {
        my ( $self, $c ) = @_;
        $c->stash->{template} = 'message.html';
        $c->forward('MyApp::View::Tenjin');
    }

If a stash item isn't defined, then it instead uses the
stringification of the action dispatched to (as defined by $c->action)
in the above example, this would be C<message>, but because the default
is to append '.html', it would load C<root/message.html>.

The items defined in the stash are passed to Tenjin for use as
template variables.

    sub default : Private {
        my ( $self, $c ) = @_;
        $c->stash->{template} = 'message.html';
        $c->stash->{message}  = 'Hello World!';
        $c->forward('MyApp::View::Tenjin');
    }

A number of other template variables are also added:

    $c      A reference to the context object, $c
    $base   The URL base, from $c->req->base()
    $name   The application name, from $c->config->{name}

These can be accessed from the template in the usual way:

<message.html>:

    The message is: [== $message =]
    The base is [== $base =]
    The name is [== $name =]

The output generated by the template is stored in C<< $c->response->body >>.

=head3 MANUALLY PROVIDING TEMPLATES

Catalyst::View::Tenjin adds an easy method for providing your own templates,
such that you do not have to use template files stored on the file system.
For example, you can use templates stored on a DBIx::Class schema. This is
similar to L<Template Toolkit|Template>'s provider modules, which for some
reason I never managed to get working. You can register templates with
your application, and use them on the fly. For example:

	# check if the template was already registered
	unless ($c->view('Tenjin')->check_tmpl($template_name)) {
		# Load the template
		my $tmpl = $c->model('DB::Templates')->find($template_name);
		$c->view('Tenjin')->register($template_name, $tmpl->content);
	}

=head2 CAPTURING TEMPLATE OUTPUT

If you wish to use the output of a template for some other purpose than
displaying in the response, you can use the L<render> method. For example,
use can use it was L<Catalyst::Plugin::Email>:

	sub send_email : Local {
		my ($self, $c) = @_;

		$c->email(
			header => [
				To      => 'me@localhost',
				Subject => 'A TT Email',
			],
			body => $c->view('Tenjin')->render($c, 'email.html', {
				additional_template_paths => [ $c->config->{root} . '/email_templates'],
				email_tmpl_param1 => 'foo'
			}),
		);
		# Redirect or display a message
	}

=head2 METHODS

=head2 new

The constructor for the Tenjin view. Sets up the template provider, 
and reads the application config.

=head2 process

Renders the template specified in C<< $c->stash->{template} >> or
C<< $c->action >> (the private name of the matched action. Calls L<render> to
perform actual rendering. Output is stored in C<< $c->response->body >>.

=head2 render($c, $template, \%args)

Renders the given template and returns output, or throws an exception
if an error was encountered.

C<$template> is the name of the template you wish to render. If this template
was not registered with the view yet, it will be searched for in the directories
set in the INCLUDE_PATH option.

The template variables are set to C<%$args> if $args is a hashref, or 
$C<< $c->stash >> otherwise. In either case the variables are augmented with 
C<base> set to C< << $c->req->base >>, C<c> to C<$c> and C<name> to
C<< $c->config->{name} >>. Alternately, the C<CATALYST_VAR> configuration item
can be defined to specify the name of a template variable through which the
context reference (C<$c>) can be accessed. In this case, the C<c>, C<base> and
C<name> variables are omitted.

=head2 register($tmpl_name, $tmpl_content)

Registers a template with the view from an arbitrary source, for immediate
usage in the application. C<$tmpl_name> is the name of the template, used
to distinguish it from others. C<$tmpl_content> is the body of the template.

=head2 check_tmpl($template_name)

Checks if a template named C<$template_name> was already registered with
the view. Returns 1 if yes, C<undef> if no.

=head2 template_vars

Returns a list of keys/values to be used as the catalyst variables in the
template.

=head1 SEE ALSO

L<Tenjin>, L<Catalyst>, L<Catalyst::View::TT>

=head1 AUTHOR

Ido Perelmutter E<lt>ido50@yahoo.comE<gt>. This module was adapted from
L<Catalyst::View::TT>, so most of the code and even the documentation
belongs to the authors of L<Catalyst::View::TT>.

=head1 COPYRIGHT & LICENSE

Copyright (c) 2009 the aforementioned authors.

This program is free software, you can redistribute it and/or modify it 
under the same terms as Perl itself.

=cut