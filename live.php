<?php
// Live link with the game (SolverBridge.gd).
//  POST {opponent, game}  - the game sends the player's current position.
//                           The solver analyzes it; the result is stored and a short hint is returned.
//  GET                    - the solver page polls the latest position + analysis.
set_time_limit(120);
header('Content-Type: application/json');
header('Cache-Control: no-store');

$stateFile = __DIR__ . DIRECTORY_SEPARATOR . 'live_state.json';

function runSolver(array $problem) {
    $solver = __DIR__ . DIRECTORY_SEPARATOR . 'websolver' . (PHP_OS_FAMILY === 'Windows' ? '.exe' : '');
    $null = PHP_OS_FAMILY === 'Windows' ? 'NUL' : '/dev/null';
    $process = proc_open([$solver], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['file', $null, 'w']], $pipes, __DIR__);
    if (!is_resource($process))
        return ['error' => 'Failed to create process.'];
    fwrite($pipes[0], json_encode($problem));
    fclose($pipes[0]);
    $out = stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    proc_close($process);
    $analysis = json_decode($out, true);
    return is_array($analysis) ? $analysis : ['error' => 'Bad solver output.'];
}

function pct($x) { return number_format($x * 100, 1) . '%'; }

/// Options of a choice that reach the best score.
function bestOptions(array $choice) {
    $best = [];
    foreach ($choice['options'] as $o)
        if (abs($o['outcome'] - $choice['score']) < 1e-9) $best[] = $o;
    return $best;
}

/// The first "Which item will you steal?" choice in the analysis, as "a Beer / an Inverter", or null.
function stealHint(array $a) {
    foreach ($a['events'] ?? [] as $e)
        if (isset($e['choice']) && $e['choice']['description'] === 'Which item will you steal?')
            return implode(' / ', array_map(fn($o) => $o['description'], bestOptions($e['choice'])));
    return null;
}

/// One-line hint for the in-game overlay.
/// $problem is needed to look up the best item to steal when Adrenaline is the best move.
function makeHint(array $a, array $problem) {
    if (isset($a['error'])) return 'error: ' . $a['error'];
    if (isset($a['validationError'])) return 'cannot analyze: ' . $a['validationError']['message'];
    $events = $a['events'] ?? [];
    if (count($events) < 2 || !isset($events[0]['start'])) return 'no analysis';
    $choice = $events[1]['choice'] ?? null;
    if (!$choice || $choice['mode'] !== 'best') return 'win chance ' . pct($events[0]['start']);
    $best = bestOptions($choice);
    if (count($best) == count($choice['options']))
        return 'any move (' . pct($choice['score']) . ')';

    $parts = [];
    foreach ($best as $o) {
        $text = $o['description'];
        if ($text === 'Use Adrenaline') {
            // Which item to steal? It is in this analysis if Adrenaline is the line being followed,
            // otherwise ask the solver for the Adrenaline line explicitly.
            $steal = stealHint($a);
            if ($steal === null)
                $steal = stealHint(runSolver($problem + ['decisions' => $o['decisions']]));
            if ($steal !== null)
                $text .= ' -> steal ' . $steal;
        }
        $parts[] = $text;
    }

    $approx = '';
    $last = end($events);
    if (isset($last['message']) && strpos($last['message'], 'Approximate') === 0) $approx = ' ~';
    return implode(' / ', $parts) . ' (' . pct($choice['score']) . $approx . ')';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $in = json_decode(file_get_contents('php://input'), true);
    if (!is_array($in) || !isset($in['game']) || !is_array($in['game'])) {
        echo json_encode(['error' => 'bad request']);
        exit;
    }
    $problem = ['opponent' => ($in['opponent'] ?? 'game') === 'perfect' ? 'perfect' : 'game', 'game' => $in['game']];
    $analysis = runSolver($problem);

    $prev = @json_decode(@file_get_contents($stateFile), true);
    $version = (is_array($prev) ? ($prev['version'] ?? 0) : 0) + 1;
    $state = ['version' => $version, 'time' => time(), 'problem' => $problem, 'analysis' => $analysis];
    file_put_contents($stateFile, json_encode($state), LOCK_EX);

    echo json_encode(['version' => $version, 'hint' => makeHint($analysis, $problem)]);
} else {
    if (!file_exists($stateFile)) {
        echo json_encode(['version' => 0]);
        exit;
    }
    $since = isset($_GET['since']) ? (int)$_GET['since'] : -1;
    $state = json_decode(file_get_contents($stateFile), true);
    if (is_array($state) && $state['version'] <= $since)
        echo json_encode(['version' => $state['version']]); // nothing new
    else
        readfile($stateFile);
}
