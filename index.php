<!doctype html>
<head>
	<meta charset="UTF-8">
	<meta name="darkreader-lock"> <!-- SVG rendering in backgrounds is broken in Dark Reader -->
	<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0">

	<title>Buckshot Roulette solver</title>
</head>

<div id="page">
	<!-- <object id="game" data="board.svg?<?php echo(filemtime("board.svg")) ?>"></object> -->
	<?php readfile('board.svg'); ?>
	<div id="explorer">
		<table>
			<tr id="explorer-header">
				<th></th>
				<th>Analysis</th>
				<th>Win %</th>
			</tr>
		</table>
	</div>
	<select id="opponent">
		<option value="game">Game dealer AI</option>
		<option value="perfect">Perfect opponent</option>
	</select>
</div>

<!--
<div id="game">
	<select id="opponent">
		<option value="game">Game dealer AI</option>
		<option value="perfect">Perfect opponent</option>
	</select>
	<div class="opp-move" id="opp-move-0"></div>
	<div class="opp-move" id="opp-move-1"></div>
	<div class="opp-move" id="opp-move-2"></div>
	<div class="board" id="board-other">
		<div class="die" id="die-0"></div>
		<div class="die" id="die-1"></div>
		<div class="die" id="die-2"></div>
		<div class="die" id="die-3"></div>
		<div class="die" id="die-4"></div>
		<div class="die" id="die-5"></div>
		<div class="die" id="die-6"></div>
		<div class="die" id="die-7"></div>
		<div class="die" id="die-8"></div>
	</div>
	<div class="board" id="board-current">
		<div class="die" id="die-9"></div>
		<div class="die" id="die-10"></div>
		<div class="die" id="die-11"></div>
		<div class="die" id="die-12"></div>
		<div class="die" id="die-13"></div>
		<div class="die" id="die-14"></div>
		<div class="die" id="die-15"></div>
		<div class="die" id="die-16"></div>
		<div class="die" id="die-17"></div>
	</div>
	<div id="tray">
		<div class="die" id="die-18"></div>
	</div>
	<div id="flip" title="Click here to flip the board">⇕</div>
	<div id="reset" title="Click here to reset the board">↻</div>
	<div id="status-badinput">Please fix&nbsp;<span class="error">errors</span></div>
	<div id="status-loading">Loading...</div>
	<div id="status-error">Error</div>
	<div class="result" id="result-0"></div>
	<div class="result" id="result-1"></div>
	<div class="result" id="result-2"></div>
	<div id="help"><div>?</div></div>
	<div id="help-page">
		<div>
			<p>Usage:</p>

			<ol>
				<li>
					<p>Draw the board you want to get a solution for by clicking/tapping on the spaces.</p>
					<p>You can also use the mouse wheel to quickly select items.</p>
					<p>Right click / long tap a slot to clear it.</p>
				</li>
			</ol>

			<p>You will see the best move (or moves, if they're equivalent) highlighted in green.</p>

			<p>Your chances of winning (assuming perfect play) are displayed below.  You can tap on the results to "accept" the move and apply it to the board.</p>

			<p>If you see any red squares while drawing the board, these are errors. Fix them, or hover over the error to see what the problem is.</p>

			<p>Click ↻ to reset the board to a new game. You can use your web browser back and forward buttons to undo / redo.</p>

			<p>The solver always assumes that it's your (the bottom player's) turn. The ⇕ button flips the board around, if you want to examine your opponent's options.</p>

			<p>Note that some answers may seem counter-intuitive at first glance. They are correct anyway.</p>

			<p>Links:</p>
			<ul>
				<li><a href="https://gitlab.com/CyberShadow/cult-of-the-lamb-knucklebones">Source code</a></li>
				<li><a href="https://steamcommunity.com/app/1313140/discussions/0/5267542371389134136/">Discussion</a></li>
				<li><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=2848999174">Guide with more information about Knucklebones</a></li>
			</ul>
		</div>
	</div>
</div>
-->

<link rel="stylesheet" href="style.css?<?php echo(filemtime("style.css")) ?>">
<script src="script.js?<?php echo(filemtime("script.js")) ?>"></script>
