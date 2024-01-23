<?php
header('Content-Type: application/json');
passthru('./websolver ' . escapeshellarg(file_get_contents('php://input')), $result_code);
if ($result_code != 0) {
    echo '{"error":' . $result_code . '}';
}
