const defaultGame = {
	currentTurn: 'player',
	shells: ['live', 'live', 'blank', null, null, null, null, null],
	items: [
		[null, null, null, null, null, null, null, null],
		[null, null, null, null, null, null, null, null]
	],
	nextShell: null,
	health: [2, 2],
	handcuffs: [null, null],
	shotgunSawedOff: false,
};

let currentGame = defaultGame;
let showGameFuncs = [];

function showGame(game) {
	document.querySelectorAll('.value').forEach(e => e.remove());
	document.querySelectorAll('.error').forEach(e => e.style.removeProperty('fill'));
	for (let func of showGameFuncs)
		func(game);
}

function copyGame(game) { return JSON.parse(JSON.stringify(game)); }

document.addEventListener('DOMContentLoaded', function() {
	function addControl(type, slot, path, values, valueIDs) {
		let slotID = 'slot-' + type + (slot !== null ? '-' + slot : '');
		let slotNode = document.getElementById(slotID);
		slotNode.style.cursor = 'pointer';

		function getValue(game) {
			let v = game;
			for (let step of path)
				v = v[step];
			return v;
		}
		function setValue(game, value) {
			let v = game;
			for (let step of path.slice(0, -1))
				v = v[step];
			v[path[path.length-1]] = value;
		}

		function cycleValue(indexUpdateFun) {
			let oldValue = getValue(currentGame);
			let oldValueIndex = values.indexOf(oldValue);
			let newValueIndex = indexUpdateFun(oldValueIndex);
			newValueIndex = (newValueIndex + values.length) % values.length;
			let newValue = values[newValueIndex];
			setValue(currentGame, newValue);

			validate();
		}

		slotNode.addEventListener('mousedown', function(event) {
			if (event.button == 0) {
				cycleValue(index => index + 1);
				event.preventDefault();
			}
		});
		slotNode.addEventListener('wheel', function(event) {
			cycleValue(index => index + Math.sign(event.deltaX + event.deltaY));
			event.preventDefault();
		});
		slotNode.addEventListener('contextmenu', function(event) {
			cycleValue(index => 0);
			event.preventDefault();
		});

		showGameFuncs.push((game) => {
			let value = getValue(game);
			let valueIndex = values.indexOf(value);
			if (typeof valueIDs === 'function')
				valueIDs(value);
			else {
				let valueID = valueIDs[valueIndex];
				if (valueID !== null) {
					valueID = type + '-' + valueID;

					let valueNode = document.createElementNS("http://www.w3.org/2000/svg", 'use');
					valueNode.setAttribute('class', 'value');
					valueNode.setAttributeNS("http://www.w3.org/1999/xlink", 'href', '#' + valueID);
					slotNode.appendChild(valueNode);
				}
			}
		});
	}
	addControl('handle', null, ['currentTurn'], ['player', 'dealer'], (currentTurn) => {
		let e = document.getElementById('board');
		e.classList.toggle('dealer-turn', currentTurn === 'dealer');
	});
	for (let i = 0; i < defaultGame.shells.length; i++)
		addControl('shell', i, ['shells', i], [null, 'blank', 'live'], [null, 'blank', 'live']);
	addControl('shell', 'next', ['nextShell'], [null, 'blank', 'live'], ['unknown', 'blank', 'live']);
	for (let c = 0; c < defaultGame.items.length; c++)
		for (let i = 0; i < defaultGame.items[c].length; i++)
			addControl('item', c + '-' + i, ['items', c, i],
					   [null, 'lookingGlass', 'handcuffs', 'beer', 'cigarettePack', 'handSaw'],
					   [null, 'lookingGlass', 'handcuffs', 'beer', 'cigarettePack', 'handSaw']);
	for (let c = 0; c < defaultGame.health.length; c++)
		addControl('health', c, ['health', c], [4, 3, 2, 1], ['4', '3', '2', '1']);
	for (let c = 0; c < defaultGame.handcuffs.length; c++)
		addControl('handcuffs', c, ['handcuffs', c],
				   [null, 'willSkip', 'willBreak'],
				   [null, 'willSkip', 'willBreak']);
	addControl('barrel', null, ['shotgunSawedOff'], [false, true], [null, 'cutoff']);

	// TODO load game from URL
	validate();
});

// function getDieValue(dieIndex) { return parseInt(getDie(dieIndex).dataset.value); }

// function getDieIndex(player, row, column) { return player * 9 + row * 3 + column; }
// function getDiePosition(dieIndex) { return { player: Math.floor(dieIndex / 9), row: Math.floor(dieIndex % 9 / 3), column: dieIndex % 3 }; }

// function cycleDie(dieIndex, delta) { setDieValue(dieIndex, (getDieValue(dieIndex) + delta + 7) % 7); }

// function clearDie(dieIndex) {
// 	setDieValue(dieIndex, 0);

// 	function dropDie(player, row, column) {
// 		const dieIndex = getDieIndex(player, row, column);
// 		const nextRowDir = [1, -1][player];
// 		const prevRow = row - nextRowDir;
// 		if (prevRow >= 0 && prevRow < numRows) {
// 			const prevDieIndex = getDieIndex(player, prevRow, column);
// 			const prevDieValue = getDieValue(prevDieIndex);
// 			setDieValue(dieIndex, prevDieValue);
// 			setDieValue(prevDieIndex, 0);
// 			dropDie(player, prevRow, column);
// 		}
// 	}

// 	const { player, row, column } = getDiePosition(dieIndex);
// 	if (player < numPlayers)
// 		dropDie(player, row, column);
// }

// function flipBoard() {
// 	for (let row = 0; row < numRows; row++) {
// 		for (let column = 0; column < numColumns; column++) {
// 			const indexA = getDieIndex(0,               row, column);
// 			const indexB = getDieIndex(1, numRows - 1 - row, column);
// 			const a = getDieValue(indexA);
// 			const b = getDieValue(indexB);
// 			setDieValue(indexA, b);
// 			setDieValue(indexB, a);
// 		}
// 	}
// }

// function resetBoard() {
// 	for (let dieIndex = 0; dieIndex < numDice; dieIndex++)
// 		setDieValue(dieIndex, 0);
// }

// function save() {
// 	let result = '';

// 	for (let dieIndex = 0; dieIndex < numDice; dieIndex++)
// 		result += getDieValue(dieIndex).toString();

// 	result += '/' + document.getElementById('opponent').value;
// 	return result;
// }

// function load(state) {
// 	if (state.length < numDice) throw 'State too short';
// 	for (let dieIndex = 0; dieIndex < numDice; dieIndex++)
// 		setDieValue(dieIndex, parseInt(state[dieIndex]));
// 	if (state[numDice] != '/') throw 'Expected /';
// 	document.getElementById('opponent').value = state.substr(numDice + 1);
// 	validate();
// }

// const numDice = 9 * 2 + 1;
// const numPlayers = 2;
// const numColumns = 3;
// const numRows = 3;

// const trayDieIndex = numDice - 1;

const winPercentFormatter = new Intl.NumberFormat('en-US', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
  style: 'percent'
});
const choiceProbabilityFormatter = new Intl.NumberFormat('en-US', {
  maximumFractionDigits: 0,
  style: 'percent'
});

var choiceCounter = 0;

function node(tagName, attributes, children) {
	let e = document.createElement(tagName);
	if (typeof attributes !== 'undefined')
		for (let name in attributes)
			e.setAttribute(name, attributes[name]);
	if (typeof children !== 'undefined') {
		if (typeof children === 'string')
			e.textContent = children;
		else {
			if (!Array.isArray(children))
				children = [children];
			for (let child of children) {
				if (typeof child === 'string')
					child = document.createTextNode(child);
				e.appendChild(child);
			}
		}
	}
	return e;
}

function addAnalysis(problem, data, rowAfter) {
	const origProblem = problem;
	while (rowAfter.nextSibling)
		rowAfter.nextSibling.remove();

	function addEvent(icon, text, winPercent) {
		const tr = node('TR', {}, [
			node('TD', {}, icon),
			node('TD', {}, text),
			node('TD', {}, winPercent === undefined || winPercent === null
				 ? undefined
				 : winPercentFormatter.format(winPercent)
			)
		]);
		rowAfter.parentElement.appendChild(tr);
		return tr;
	}

	function gameLink(o) {
		const link = node('A', {href: '#' + o.packedGame + '/' + problem.opponent}, 'Game #' + o.packedGame);
		link.addEventListener('click', function(e) {
			e.preventDefault();
			// TODO: use history.pushState instead
			currentGame = copyGame(o.game);
			validate(true);
		});
		return link;
	}

	if ('error' in data) {
		addEvent('💥', 'Fatal error: ' + data.error);
		return;
	}
	if ('validationError' in data) {
		addEvent('💥', 'Invalid game: ' + data.validationError.message);
		for (let id of data.validationError.ids) {
			let e = document.getElementById('slot-' + id);
			e.classList.add('error');
			e.style.fill = '#faa';
		}
		return;
	}

	for (let event of data.events) {
		if ('message' in event)
			addEvent('ℹ️', event.message);
		else
		if ('start' in event)
			addEvent('🚀', ['Analyzing ', gameLink(data), '.'], event.start);
		else
		if ('choice' in event) {
			choiceCounter++;
			let icon =
				event.choice.mode == 'best' ? '🤔' :
				event.choice.mode == 'worst' ? '🖥️' :
				event.choice.mode == 'random' ? '🎲' :
				event.choice.mode == 'randomWithDuplicates' ? '🎲' :
				event.choice.mode == 'unknown' ? '❓' :
				'';
			addEvent(icon,
					 event.choice.description,
					 'selectedOption' in event.choice
					 ? event.choice.options[event.choice.selectedOption].outcome
					 : undefined);
			let lastRow;
			for (let i = 0; i < event.choice.options.length; i++) {
				let option = event.choice.options[i];
				let description = option.description;
				if ('probability' in option)
					description = '[' + choiceProbabilityFormatter.format(option.probability) + '] ' + description;
				let radio = node('INPUT', {
					type: 'radio',
					name: 'choice-' + choiceCounter,
					id: 'choice-' + choiceCounter + '-' + i,
					value: i
				});
				if ('selectedOption' in event.choice && i == event.choice.selectedOption)
					radio.checked = 'checked';
				let label = node('LABEL', { for: radio.id }, [
					radio,
					description,
				]);
				radio.addEventListener('change', function() {
					const problem = {
						opponent: origProblem.opponent,
						game: data.game,
						decisions: option.decisions,
					};
					fetch('websolver.php', {
						method: 'POST',
						headers: {
							'Content-Type': 'application/json',
						},
						body: JSON.stringify(problem),
					})
					.then((response) => response.json())
					.then((data) => {
						addAnalysis(
							problem,
							data,
							lastRow,
						);
					})
					.catch((error) => {
						console.log(error);
					});
				});
				lastRow = addEvent('➡️', label, option.outcome);
			}
		}
		else
		if ('recursion' in event) {
			addEvent('📍', ['Checkpoint: ', gameLink(event.recursion), '.'], event.recursion.score);
		}
		else
		if ('gameOver' in event) {
			addEvent(event.gameOver ? '✌️' : '💀', 'Game over.', event.gameOver ? 1 : 0);
		}
	}
}

let boardVersion = 0;

function validate(now) {
	showGame(currentGame);

	boardVersion++;

	// let errors = new Array(numDice);
	// let haveFatalErrors = false;
	// for (let dieIndex = 0; dieIndex < numDice; dieIndex++)
	// 	errors[dieIndex] = null;

	// for (let player = 0; player < numPlayers; player++)
	// 	for (let column = 0; column < numColumns; column++)
	// 		for (let row = 0; row < numRows; row++) {
	// 			const dieIndex = getDieIndex(player, row, column);
	// 			const dieValue = getDieValue(dieIndex);

	// 			const nextRowDir = [1, -1][player];
	// 			const nextRow = row + nextRowDir;
	// 			if (nextRow >= 0 && nextRow < numRows) {
	// 				const nextDieIndex = getDieIndex(player, nextRow, column);
	// 				const nextDieValue = getDieValue(nextDieIndex);
	// 				if (dieValue != 0 && nextDieValue == 0) {
	// 					errors[dieIndex] = 'There is a blank space below this die.';
	// 					haveFatalErrors = true;
	// 				}
	// 			}

	// 			if (dieValue != 0) {
	// 				for (let otherRow = 0; otherRow < numRows; otherRow++) {
	// 					const otherDieIndex = getDieIndex(1 - player, otherRow, column);
	// 					const otherDieValue = getDieValue(otherDieIndex);
	// 					if (otherDieValue == dieValue) {
	// 						errors[dieIndex] = 'The same die face cannot occur on both sides of the board.';
	// 						haveFatalErrors = true;
	// 					}
	// 				}
	// 			}

	// 			const lastRow = [0, 2][player];
	// 			if (dieValue != 0 && row == lastRow) {
	// 				let haveRoom = false;
	// 				for (let otherColumn = 0; otherColumn < numColumns; otherColumn++) {
	// 					const otherDieIndex = getDieIndex(player, row, otherColumn);
	// 					const otherDieValue = getDieValue(otherDieIndex);
	// 					if (otherDieValue == 0)
	// 						haveRoom = true;
	// 				}
	// 				if (!haveRoom) {
	// 					errors[dieIndex] = 'There is no room to place any more dice. The game is over.';
	// 					haveFatalErrors = true;
	// 				}
	// 			}
	// 		}

	// if (getDieValue(trayDieIndex) == 0)
	// 	errors[trayDieIndex] = 'Please select the rolled die.';

	// for (let dieIndex = 0; dieIndex < numDice; dieIndex++) {
	// 	const die = getDie(dieIndex);
	// 	if (errors[dieIndex]) {
	// 		die.classList.add('error');
	// 		die.title = errors[dieIndex];
	// 	} else {
	// 		die.classList.remove('error');
	// 		die.title = '';
	// 	}
	// 	die.classList.remove('best');
	// }

	// for (const id of ['status-badinput', 'status-loading', 'status-nodie', 'status-error', 'result-0', 'result-1', 'result-2', 'opp-move-0', 'opp-move-1', 'opp-move-2'])
	// 	document.getElementById(id).style.display = 'none';

	// if (haveFatalErrors) {
	// 	document.getElementById('status-badinput').style.display = 'flex';
	// 	return;
	// }

	// if (getDieValue(trayDieIndex)) {
	// 	for (let column = 0; column < numColumns; column++) {
	// 		if (getDieValue(getDieIndex(0, 0, column)) == 0) {
	// 			const oppMove = document.getElementById('opp-move-' + column);
	// 			oppMove.style.display = 'block';
	// 			oppMove.innerHTML = '<div class="arrow">▼</div>';
	// 			oppMove.title = "You can click here to place the rolled die on the opponent's table in this column.";
	// 		}
	// 	}
	// }

	const requestVersion = boardVersion;
	setTimeout(function() {
		if (requestVersion != boardVersion)
			return;

		// const state = save();
		// const hash = '#' + state;
		// if (hash != window.location.hash)
		// 	window.location = hash;  // Push state

		// document.getElementById('status-loading').style.display = 'flex';

		const problem = {
			opponent: document.getElementById('opponent').value,
			game: currentGame,
		};

		fetch('websolver.php', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
			},
			body: JSON.stringify(problem),
		})
		.then((response) => response.json())
		.then((data) => {
			if (requestVersion != boardVersion)
				return; // outdated

			addAnalysis(
				problem,
				data,
				document.getElementById('explorer-header'),
			);
			// document.getElementById('status-loading').style.display = 'none';
			// if (data.bestMoves.length == 0) {
			// 	const nodie = document.getElementById('status-nodie');
			// 	nodie.style.display = 'flex';
			// 	nodie.innerHTML = '<div>Chance of winning: ' + (data.currentScore * 50 + 50).toString().substring(0, 5) + '%<br>Please select the rolled die.</div>';
			// 	nodie.title = 'Assuming perfect play from both sides, your chance of winning the game is currently ' + (data.currentScore * 50 + 50) + '%.\n\nTo see the breakdown for each possible move, select the die you rolled on the left.';
			// 	return;
			// }
			// for (let column of data.bestMoves) {
			// 	for (let row = 0; row < numRows; row++) {
			// 		const dieIndex = getDieIndex(1, row, column);
			// 		const dieValue = getDieValue(dieIndex);
			// 		if (dieValue == 0) {
			// 			const die = getDie(dieIndex);
			// 			die.classList.add('best');
			// 			die.title = 'After moving here, you will have a ' + (data.scores[column] * 50 + 50) + '% chance of winning, assuming perfect play.';
			// 			break;
			// 		}
			// 	}
			// }
			// for (let column = 0; column < numColumns; column++) {
			// 	if (data.scores[column] != null) {
			// 		const result = document.getElementById('result-' + column);
			// 		result.style.display = 'block';
			// 		result.innerHTML = '<div class="arrow">▲</div>' + (data.scores[column] * 50 + 50).toString().substring(0, 5) + '%';
			// 		if (data.bestMoves.includes(column))
			// 			result.classList.add('good');
			// 		else
			// 			result.classList.remove('good');
			// 		result.title = 'If you move here, you will have a ' + (data.scores[column] * 50 + 50) + '% chance of winning, assuming perfect play.\n\nClick to move here.';
			// 	}
			// }
		})
		.catch((error) => {
			if (requestVersion != boardVersion)
				return; // outdated
			console.error(error);
			// document.getElementById('status-loading').style.display = 'none';
			// document.getElementById('status-error').style.display = 'flex';
			// document.getElementById('status-error').textContent = 'Error' + error;
		});
	}, now ? 0 : 500);
}

// function move(player, column) {
// 	const rowOrder = [[2, 1, 0], [0, 1, 2]];

// 	const dieValue = getDieValue(trayDieIndex);
// 	if (dieValue == 0)
// 		throw "Can't move with empty tray";
// 	setDieValue(trayDieIndex, 0);

// 	for (let row of rowOrder[player]) {
// 		const dieIndex = getDieIndex(player, row, column);
// 		if (getDieValue(dieIndex) == 0) {
// 			setDieValue(dieIndex, dieValue);
// 			break;
// 		}
// 	}

// 	for (let row of rowOrder[1-player]) {
// 		const dieIndex = getDieIndex(1-player, row, column);
// 		while (getDieValue(dieIndex) == dieValue) {
// 			clearDie(dieIndex);
// 		}
// 	}
// }

(function() {
// 	for (let dieIndex = 0; dieIndex < numDice; dieIndex++) {
// 		const die = getDie(dieIndex);
// 		setDieValue(dieIndex, 0);
// 		// die.addEventListener('click', function() { cycleDie(dieIndex); });
// 		// die.addEventListener('dblclick', function(event) { event.preventDefault(); });
// 		die.addEventListener('mousedown', function(event) {
// 			if (event.button == 0) {
// 				cycleDie(dieIndex, +1);
// 				validate();
// 				event.preventDefault();
// 			}
// 		});
// 		die.addEventListener('wheel', function(event) {
// 			cycleDie(dieIndex, Math.sign(event.deltaX + event.deltaY));
// 			validate();
// 			event.preventDefault();
// 		});
// 		die.addEventListener('contextmenu', function(event) {
// 			clearDie(dieIndex);
// 			validate();
// 			event.preventDefault();
// 		});
// 	}

// 	for (let column = 0; column < numColumns; column++) {
// 		const result = document.getElementById('result-' + column);
// 		result.addEventListener('mousedown', function(event) {
// 			if (event.button == 0) {
// 				move(1, column);
// 				validate(true);
// 				event.preventDefault();
// 			}
// 		});
// 		const oppMove = document.getElementById('opp-move-' + column);
// 		oppMove.addEventListener('mousedown', function(event) {
// 			if (event.button == 0) {
// 				move(0, column);
// 				validate(true);
// 				event.preventDefault();
// 			}
// 		});
// 	}

// 	document.getElementById('flip').addEventListener('click', function() {
// 		flipBoard();
// 		validate();
// 	});

// 	document.getElementById('reset').addEventListener('click', function() {
// 		resetBoard();
// 		validate(true);
// 	});

	document.getElementById('opponent').addEventListener('change', function() {
		validate(true);
	});

// 	validate(true);
// 	if (window.location.hash.length > 1) {
// 		try {
// 			load(window.location.hash.substr(1));
// 		} catch (e) {
// 			console.log(e);
// 		}
// 	}

// 	window.addEventListener('hashchange', function() {
// 		if (window.location.hash.length > 1) {
// 			const state = window.location.hash.substr(1);
// 			if (state != save())
// 				load(state);
// 		}
// 	});

	const page = document.getElementById('page');
	const pageStyle = window.getComputedStyle(page);
// 	const numUIColumns = pageStyle.gridTemplateColumns.split(' ').length;
// 	const numUIRows = pageStyle.gridTemplateRows.split(' ').length;  // same as aspect-ratio / #page grid-template
	const haveAspectRatio = 'aspectRatio' in pageStyle;

	function updateSize() {
		// // Work around no support of aspect-ratio CSS property
		// // in Steam's in-page browser
		// if (!haveAspectRatio) {
		// 	const unitSize = Math.min(
		// 		document.documentElement.clientWidth / numUIColumns,
		// 		document.documentElement.clientHeight / numUIRows
		// 	);
		// 	page.style.width = (unitSize * numUIColumns) + 'px';
		// 	page.style.height = (unitSize * numUIRows) + 'px';
		// }

		// Make it so that 2em == one grid tile.
		// (Maybe one day this will be doable in CSS...)
		// page.style.fontSize = (page.clientWidth / 2 / numUIRows) + 'px';
		page.style.fontSize = (page.clientWidth / 48) + 'px';

		window.requestAnimationFrame(updateSize);
	}
	updateSize();

// 	var helpVisible = false;
// 	document.getElementById('help').addEventListener('click', function() {
// 		helpVisible = !helpVisible;
// 		document.getElementById('help-page').style.display = helpVisible ? "block" : "none";
// 		document.querySelector('#help div').textContent = helpVisible ? '×' : '?';
// 	});
})();
