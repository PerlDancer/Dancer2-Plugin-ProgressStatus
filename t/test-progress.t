#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use File::Temp;
use YAML::Any qw/DumpFile/;
use File::Spec;

use LWP::UserAgent;
use Test::TCP 1.13;

my $dir;
## Create config settings required by plugin
BEGIN {
    $dir = File::Temp->newdir(CLEANUP => 0);
    my $file = File::Spec->catfile($dir, 'config.yml');
    DumpFile($file, { plugins => { ProgressStatus => { dir => "$dir" }}});

    $ENV{DANCER_CONFDIR} = "$dir/";
};

my $server = sub {
    my $port = shift;

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

    # we're overiding a RO attribute only for this test!
    Dancer2->runner->{'port'} = $port;
    start;
};

my $client = sub {
    my $port = shift;
    my $ua = LWP::UserAgent->new;

    my ($data, $res);

    $res = $ua->get("http://127.0.0.1:$port/test_progress_status_simple_with_no_args");
    is $res->code, 200, 'Get good res from progressstatus';

    $res = $ua->get("http://127.0.0.1:$port/_progress_status/test");
    is $res->code, 200, 'Get good res from progressstatus';
    $data = from_json($res->content);
    is($data->{total}, 100, 'Total is 100');
    is($data->{count}, 2, 'Count matches total');
    ok(!$data->{in_progress}, 'No longer in progress');

    $res = $ua->get("http://127.0.0.1:$port/test_progress_status_with_args");
    is $res->code, 200, 'Get good res from progressstatus';

    $res = $ua->get("http://127.0.0.1:$port/_progress_status/test2");
    $data = from_json($res->content);

    is($data->{total}, 200, 'Total is 200');
    is($data->{count}, 3, 'Count matches total');
    is(scalar(@{$data->{messages}}), 2, 'Has two messages');
    ok(!$data->{in_progress}, 'No longer in progress');

    $res = $ua->get("http://127.0.0.1:$port/test_progress_status_good_concurrency");
    is($res->code, 200, 'Two progress meters with the same name and same pid pass');
    like($res->content, qr/^Progress status test3 already exists/, 'two unfinished progress meters with the same name dies');

    $res = $ua->get("http://127.0.0.1:$port/_progress_status/test3");
    $data = from_json($res->content);
    is($data->{total}, 200, 'Total is overriden');

    $res = $ua->get("http://127.0.0.1:$port/test_progress_with_progress_id?progress_id=1000");
    is $res->code, 200;

    $res = $ua->get("http://127.0.0.1:$port/_progress_status/1000");
    is $res->code, 200;
    $data = from_json($res->content);
    is($data->{total}, 100, 'Get a sensible res');
};

Test::TCP::test_tcp( client => $client, server => $server);

done_testing;
