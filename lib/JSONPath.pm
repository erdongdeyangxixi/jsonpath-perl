#!/usr/bin/perl

#	JSONPath 0.8.1 - XPath for JSON
#	
#	A port of the JavaScript and PHP versions 
#	of JSONPath which is 
#	Copyright (c) 2007 Stefan Goessner (goessner.net)
#	Licensed under the MIT licence: 
#	
#	Permission is hereby granted, free of charge, to any person
#	obtaining a copy of this software and associated documentation
#	files (the "Software"), to deal in the Software without
#	restriction, including without limitation the rights to use,
#	copy, modify, merge, publish, distribute, sublicense, and/or sell
#	copies of the Software, and to permit persons to whom the
#	Software is furnished to do so, subject to the following
#	conditions:
#	
#	The above copyright notice and this permission notice shall be
#	included in all copies or substantial portions of the Software.
#	
#	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#	OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#	HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#	WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#	OTHER DEALINGS IN THE SOFTWARE.




package JSONPath;
use strict;
use lib '../../lib';
use JSON;


sub new(){
	my $class = shift;
	my $self = bless {
		obj => undef,
		result_type => 'VALUE',
		result => [],
		subx => [],
		reserved_locs => {
			'*' => undef,
			'..' => undef,
		}
	}, $class;
	return $self;

}

sub run(){
	my $self = shift;
	$self->{'result'} = (); #reset it
	$self->{'obj'} = undef;
	my ($obj, $expr, $arg) = @_;
	#my $self->{'obj'} = $obj;
	##$self->logit( "arg: $arg");
	if ($arg && $arg->{'result_type'}){
		my $result_type = $arg->{'result_type'};
		if ($result_type eq 'PATH' | $result_type eq 'VALUE'){
			$self->{'result_type'} = $arg->{'result_type'};
		}
	}
	if ($expr and $obj and ($self->{'result_type'} eq 'VALUE' || $self->{'result_type'} eq 'PATH')){
		my $cleaned_expr = $self->normalize($expr);
		$cleaned_expr =~ s/^\$;//;
		$self->trace($cleaned_expr, $obj, '$');
		my @result = @{$self->{'result'}};
		
		#print STDERR " ending. result = @result\n";

		if ($#result > -1){
			#print STDERR " will return result\n";
			return \@result;
		} 
		#print STDERR "will return zero\n";
		return 0;
	}
}



=nd 
normalize the path expression;

=cut
sub normalize (){
	my $self = shift;
	my $x = shift;
	$x =~ s/"\/[\['](\??\(.*?\))[\]']\/"/&_callback_01($1)/eg;
	$x =~ s/'?(?<!@)\.'?|\['?/;/g; #added the negative lookbehind -krhodes
	$x =~ s/;;;|;;/;..;/g;
	$x =~ s/;$|'?\]|'$//g;
	$x =~ s/#([0-9]+)/&_callback_02($1)/eg;
	$self->{'result'} = [];
	return $x;
}


sub as_path(){
	my $self = shift;
	my $path = shift;
	
	my @x = split(/;/, $path);
	my $p = '$';
	#the JS and PHP versions of this are totally whack
	foreach my $piece (@x){
		$p .= "[$x[$piece]]";
	}
	return $p;
}

sub store(){
	my $self = shift;
	my $path = shift;
	my $object = shift;
	if ($path){
		if ($self->{'result_type'} eq 'PATH'){
			push @{$self->{'result'}}, $self->as_path($path);
		} else {
			push @{$self->{'result'}}, $object;
		}
	}
	#print STDERR "-Updated Result to: \n";
	foreach my $res (@{$self->{'result'}}){
		#print STDERR "-- $res\n";
	} 
	
	return $path;
}

sub trace(){
	##$self->logit( "raw trace args: @_");
	my $self = shift;
	my ($expr, $obj, $path) = @_;
	#$self->logit( "in trace. $expr /// $obj /// $path");
	if ($expr){
		my @x = split(/;/, $expr);
		my $loc = shift(@x);
		my $x_string = join(';', @x);
		my $ref_type = ref $obj;
		my $reserved_loc = 0;
		if (exists $self->{'reserved_locs'}->{$loc}){
			$reserved_loc = 1;
		}
		
		
		if (! $reserved_loc and  $ref_type eq 'HASH' and ($obj and exists $obj->{$loc}) ){ 
			#$self->logit( "tracing loc($loc) obj (hash)?");
			$self->trace($x_string, $obj->{$loc}, $path . ';' . $loc);
		} elsif (! $reserved_loc and $ref_type eq 'ARRAY' and ($loc =~ m/^\d+$/ and  $#{$obj} >= $loc and $obj->[$loc] != undef)   ) {
			$self->trace($x_string, $obj->[$loc], $path . ';' . $loc);
			
		} elsif ($loc eq '*'){
			#$self->logit( "tracing *");
			$self->walk($loc, $x_string, $obj, $path, \&_callback_03);
		} elsif ($loc eq '!'){
			#$self->logit( "tracing !");
			$self->walk($loc, $x_string, $obj, $path, \&_callback_06);
		} elsif ($loc eq '..'){
			#$self->logit( "tracing ..");
			$self->trace($x_string, $obj, $path);
			$self->walk($loc, $x_string, $obj, $path, \&_callback_04);
		} elsif ($loc =~ /,/){
			#$self->logit( "tracing loc w comma");
			foreach my $piece ( split(/'?,'?/, $loc)){
				$self->trace($piece . ';' . $x_string, $obj, $path);
			}
		} elsif ($loc =~ /^\(.*?\)$/){
			#$self->logit( "tracing loc /^\(.*?\)\$/");
			my $path_end = $path;
			$path_end =~ s/.*;(.).*?$/$1/;
			$self->trace($self->eobjuate($loc, $obj, $path_end . ';' . $x_string, $obj, $path));
		} elsif ($loc =~ /^\?\(.*?\)$/){
			#$self->logit( "tracing loc /^\?\(.*?\)\$/");
			$self->walk($loc, $x_string, $obj, $path, \&_callback_05);
			#$self->logit( "after walk w/ 05");
		} elsif ($loc =~ /^(-?[0-9]*):(-?[0-9]*):?([0-9]*)$/){
			#$self->logit( "tracing loc for slice");
			$self->slice($loc, $x_string, $obj, $path);
		}
	} else {
		#$self->logit( "trace no expr. will store $obj");
		$self->store($path, $obj);
	}
	#$self->logit( "leaving trace");
}

sub walk (){
	my $self = shift;
	my ($loc, $expr, $obj, $path, $funct) = @_;
	#$self->logit( "in walk. $loc /// $expr /// $obj /// $path ");
	
	if (ref $obj eq 'ARRAY'){
		
		for (my $i = 0; $i <= $#{$obj}; $i++){
			#$self->logit( "before Array func call: w/ $i /// $loc /// $expr /// $obj /// $path");
			$funct->($self, $i, $loc, $expr, $obj, $path); 
			#$self->logit( "after func call");
			
		}
	} elsif (ref $obj eq 'HASH') { # a Hash 
		my @keys = keys %{$obj};
		#print STDERR "$#keys keys in hash to iterate over:\n";
		foreach my $key (@keys){
			#$self->logit( "before Hash func call: w/ $key /// $loc /// $expr /// $obj /// $path");
			$funct->($self, $key, $loc, $expr, $obj, $path); 
			#$self->logit( "after func call");
		}
				
	}
	#$self->logit( " leaving walk");
}

sub slice(){
	my $self = shift;
	#$self->logit( "in slice");
	my ($loc, $expr, $obj, $path) = @_;
	$loc =~ s/^(-?[0-9]*):(-?[0-9]*):?(-?[0-9]*)$/$1:$2:$3/;
	my @s = split ($loc);

	my $len = 0;
	if (ref $obj eq 'HASH'){
		$len = $#{keys %{$obj}};
	} else { #array
		$len = $#{$obj};
	}
	my $start = $s[0] ? $s[0] : 0;
	my $end = $s[1] ? $s[1] : $len; 
	my $step = $s[2] ? $s[2] : 1;
	$start = $start < 0 ? ($start + $len > 0 ? $start + $len : 0) : ($len > $start ? $start : $len); 
	$end = $end < 0 ? ($end + $len > 0 ? $end + $len : 0) : ($len > $end ? $end : $len); 
	for (my $x = $start; $x < $end-1; $x += $step){
		$self->trace("$x;$expr", $obj, $path);
	}
}

sub evalx(){
	my $self = shift;
	my ($loc, $obj) = @_;
	#$self->logit( "in evalx: $loc /// $obj");
	#x: @.price<10: [object Object] _vname: 0
	#need to convert @.price<10 to 
	#$obj->{'price'} < 10
	#and then evaluate
	#
	#x: @.isbn
	#needs to convert to 
	#exists $obj->{'isbn'}
	if ($loc =~ m/$@\.[a-zA-Z0-9_-]*$/){
		$loc =~ s/@\.([a-zA-Z0-9_-]*)$/exists \$obj->{'$1'}/;
	} else { # it's a comparis on some sort?
		$loc =~ s/@\.([a-zA-Z0-9_-]*)(.*)/\$obj->{'$1'}$2/;
		$loc =~ s/(?<!=)(=)(?!=)/==/; #convert single equals to double
	}
	#print STDERR "loc: $loc\n";
	return ($obj and $loc and eval($loc)) ? 1 : 0;
}

sub _callback_01(){
	my $self = shift;
	#$self->logit( "in 01");
	my $arg = shift;
	push @{$self->{'result'}}, $arg;
	return '[#' . $#{$self->{'result'}} . ']';
}

sub _callback_02 {
	my $self = shift;
	#$self->logit( "in 02");
	my $arg = shift;
	return @{$self->{'result'}}[$arg];
}


sub _callback_03(){
	my $self = shift;
	#$self->logit( " in 03 ");
	my ($key, $loc, $expr, $obj, $path) = @_;
	$self ->trace($key . ';' . $expr , $obj, $path);
}

sub _callback_04(){
	my $self = shift;
	my ($key, $loc, $expr, $obj, $path) = @_;
	#$self->logit( " in 04. expr = $expr");
	if (ref $obj eq 'HASH'){
		if (ref($obj->{$key}) eq 'HASH' ){
			##$self->logit( "Passing this to trace: ..;$expr, " . $obj->{$key} . ", $path;$key\n";
			$self->trace('..;'.$expr, $obj->{$key}, $path . ';' . $key);
		} elsif (ref($obj->{$key})) { #array
			#print STDERR "--- \$obj->{$key} wasn't a hash. it was a " . (ref $obj->{$key}) . "\n";
			$self->trace('..;'.$expr, $obj->{$key}, $path . ';' . $key);
		}
	} else {
		#print STDERR "-- obj wasn't a hash. it was a " . (ref $obj) . "\n";
		if (ref($obj->[$key]) eq 'HASH' ){
			$self->trace('..;'.$expr, $obj->[$key], $path . ';' . $key);
		}
	}

}

sub _callback_05(){
	my $self = shift;
	#$self->logit( "05");
	my ($key, $loc, $expr, $obj, $path) = @_;
	$loc =~ s/^\?\((.*?)\)$/$1/;
	my $eval_result = 0;
	if (ref $obj eq 'HASH'){
		#$self->logit( " in 05 obj: $obj obj->{$key}: ". $obj->{$key});
		$eval_result = $self->evalx($loc, $obj->{$key});
	} else {
		#$self->logit( " in 05 obj: $obj obj->[$key]: ". $obj->[$key] );
		$eval_result = $self->evalx($loc, $obj->[$key]);
	}
	#$self->logit( "eval_result: $eval_result"); 
	if ($eval_result){
		$self->trace("$key;$expr", $obj, $path);
	}
	#$self->logit( "leaving 05");
}

sub _callback_06(){
	my $self = shift;
	my ($key, $loc, $expr, $obj, $path) = @_;
	#$self->logit("in 06 $key /// $loc /// $expr /// $obj /// $path" );
	if (ref $obj eq 'HASH'){
		$self->trace($expr, $key, $path);
	}
}

#my $log_count = 1;
#sub logit(){
#	my $self = shift;
#	my $message = shift;
#	print STDERR "$log_count) $message\n";
#	$log_count++;
#}

return 1;

