<?php

$descriptor_spec = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
];

$process = proc_open(array('./websolver'), $descriptor_spec, $pipes);

header('Content-Type: application/json');
if (is_resource($process)) {
    stream_copy_to_stream(fopen('php://input' , 'r'), $pipes[0]); fclose($pipes[0]);
    stream_copy_to_stream($pipes[1], fopen('php://output', 'w')); fclose($pipes[1]);
    proc_close($process);
} else {
    echo '{"error":"Failed to create process."}';
}
