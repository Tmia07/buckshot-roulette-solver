<?php
set_time_limit(120); // the solver itself stops after ~8-16 s

$descriptor_spec = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
];

$solver = __DIR__ . DIRECTORY_SEPARATOR . 'websolver' . (PHP_OS_FAMILY === 'Windows' ? '.exe' : '');
$process = proc_open(array($solver), $descriptor_spec, $pipes, __DIR__);

header('Content-Type: application/json');
if (is_resource($process)) {
    stream_copy_to_stream(fopen('php://input' , 'r'), $pipes[0]); fclose($pipes[0]);
    stream_copy_to_stream($pipes[1], fopen('php://output', 'w')); fclose($pipes[1]);
    proc_close($process);
} else {
    echo '{"error":"Failed to create process."}';
}
