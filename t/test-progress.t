#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use File::Temp;
use YAML::Any qw/DumpFile/;
use File::Spec;
use HTTP::Request::Common;
use JSON;

use Plack::Test;

my $dir;
## Create config settings required by plugin
BEGIN {
    $dir = File::Temp->newdir(CLEANUP => 0);
    my $file = File::Spec->catfile($dir, 'config.yml');
    DumpFile($file, { plugins => { ProgressStatus => { dir => "$dir" }}});

    $ENV{DANCER_CONFDIR} = "$dir/";
};

{
    package App;

    use Dancer2;
    use Dancer2::Plugin::ProgressStatus;

    get '/test_progress_status_simple_with_no_args' => sub {
        my $prog = start_progress_status('test');
        $prog++;
        $prog++; # count should be 2

        return 'ok';
    };

    get '/test_progress_status_with_args' => sub {
        my $prog = start_progress_status({
            name     => 'test2',
            total    => 200,
            count    => 0,
        });

        $prog++;
        $prog++;
        $prog++;
        $prog->add_message('Message1');
        $prog->add_message('Message2');
        # count should be 3 and messages should be size 2

        return 'ok';
    };

    get '/test_progress_status_good_concurrency' => sub {
        my $prog1 = start_progress_status({
            name    => 'test3',
            total   => 200,
        });
        my $prog2 = eval { start_progress_status('test3') }; # This should die

        if ( $@ ) {
            return $@;
        }

        return 'ok';
    };

    # Test progress status with an extra identifier
    get '/test_progress_with_progress_id' => sub {
        my $prog = start_progress_status();

        return 'ok';
    };

}

my $app = Dancer2->runner->psgi_app;
is( ref $app, 'CODE', 'Got app' );

test_psgi $app, sub {
    my $cb = shift;
    my ($data, $res);

    $res = $cb->( GET '/test_progress_status_simple_with_no_args');
    is $res->code, 200, 'Get good res from progressstatus';

    $res = $cb->( GET "/_progress_status/test");
    is $res->code, 200, 'Get good res from progressstatus';
    $data = from_json($res->content);
    is($data->{total}, 100, 'Total is 100');
    is($data->{count}, 2, 'Count matches total');
    ok(!$data->{in_progress}, 'No longer in progress');

    $res = $cb->( GET "/test_progress_status_with_args");
    is $res->code, 200, 'Get good res from progressstatus';

    $res = $cb->( GET "/_progress_status/test2");
    $data = from_json($res->content);
    is($data->{total}, 200, 'Total is 200');
    is($data->{count}, 3, 'Count matches total');
    is(scalar(@{$data->{messages}}), 2, 'Has two messages');
    ok(!$data->{in_progress}, 'No longer in progress');

    $res = $cb->( GET "/test_progress_status_good_concurrency");
    is($res->code, 200, 'Two progress meters with the same name and same pid pass');
    like($res->content, qr/^Progress status test3 already exists/, 'two unfinished progress meters with the same name dies');

    $res = $cb->( GET "/_progress_status/test3");
    $data = from_json($res->content);
    is($data->{total}, 200, 'Total is overriden');

    $res = $cb->( GET "/test_progress_with_progress_id?progress_id=1000");
    is $res->code, 200;

    $res = $cb->( GET "/_progress_status/1000");
    is $res->code, 200;
    $data = from_json($res->content);
    is($data->{total}, 100, 'Get a sensible res');
};

done_testing;
