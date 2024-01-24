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
	<div id="explorer-page">
		<table>
			<tr>
				<td id="summary">Loading...</td>
			</tr>
		</table>

		<table id="explorer">
			<tr id="explorer-header">
				<th></th>
				<th>Analysis</th>
				<th>Win %</th>
			</tr>
		</table>
	</div>
	<div id="help-page">
		<div>
			<p>Usage:</p>

			<ol>
				<li>
					<p>Input the game you want to get a solution for by clicking/tapping on the slots.</p>
					<p>You can also use the mouse wheel to quickly cycle through options.</p>
					<p>Right click / long tap a slot to clear it.</p>
				</li>
				<li>
					<p>The summary on the top right will give you a simple explanation of the situation.</p>
				</li>
				<li>
					<p>The outcome explorer on the right will display an analysis of the game.</p>

					<p>
						The <b>Win %</b> column will show the likelihood of the game ending with you winning:
						100% means that a win is guaranteed, and 0% means that a loss is guaranteed.
					</p>

					<p>
						For decisions and random events, the analysis will show how each outcome affects the <b>Win %</b>.
						You can select or change which outcome happens by selecting the corresponding option.
					</p>
				</li>
			</ol>

			<p>Click <span class="emoji">🧹</span> to reset the board to a new game. You can use your web browser back and forward buttons to undo / redo.</p>

			<p>Click <span class="emoji">🔄</span> to flip the board around, if you want to examine your opponent's options.</p>

			<p>Click <span class="emoji">❌</span> to close this help page.</p>

			<p>Links:</p>
			<ul>
				<li><a href="https://gist.github.com/CyberShadow/87d403bb29fa3047f2182c41f74e286e">Source code</a></li>
			</ul>
		</div>
	</div>
	<select id="opponent">
		<option value="game">Game dealer AI</option>
		<option value="perfect">Perfect opponent</option>
	</select>
</div>

<!--
<div id="game">
	<div id="flip" title="Click here to flip the board">⇕</div>
	<div id="reset" title="Click here to reset the board">↻</div>
	<div id="status-badinput">Please fix&nbsp;<span class="error">errors</span></div>
	<div id="status-loading">Loading...</div>
	<div id="status-error">Error</div>
	<div id="help"><div>?</div></div>
</div>
-->

<link rel="stylesheet" href="style.css?<?php echo(filemtime("style.css")) ?>">
<script src="script.js?<?php echo(filemtime("script.js")) ?>"></script>
