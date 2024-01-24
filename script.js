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

let currentGame = copyGame(defaultGame);
let showGameFuncs = [];
let resetGameFuncs = [];

function showGame(game) {
	document.querySelectorAll('.value').forEach(e => e.remove());
	document.querySelectorAll('.error').forEach(e => e.style.removeProperty('fill'));
	document.body.classList.toggle('packed-game', typeof game === 'string');
	if (typeof game === 'string')
		document.getElementById('packed-game').textContent = 'Game #' + game;
	else
		for (let func of showGameFuncs)
			func(game);
}

function copyGame(game) { return JSON.parse(JSON.stringify(game)); }

function flipBoard() {
	let game = copyGame(currentGame);
	game.currentTurn = game.currentTurn == 'player' ? 'dealer' : 'player';
	game.items.reverse();
	game.items[0].reverse();
	game.items[1].reverse();
	game.health.reverse();
	game.handcuffs.reverse();
	currentGame = game;
}

function resetBoard() {
	for (let func of resetGameFuncs)
		func(currentGame);
}

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

function addAnalysis(problem, data) {
	const origProblem = problem;
	const explorerHeader = document.getElementById('explorer-header');
	while (explorerHeader.nextSibling)
		explorerHeader.nextSibling.remove();

	function addEvent(icon, text, winPercent) {
		const tr = node('TR', {}, [
			node('TD', {}, icon),
			node('TD', {}, text),
			node('TD', {}, winPercent === undefined || winPercent === null
				 ? undefined
				 : winPercentFormatter.format(winPercent)
			)
		]);
		explorerHeader.parentElement.appendChild(tr);
		return tr;
	}

	function gameLink(o) {
		const link = node('A', {href: '#' + o.packedGame + '/' + problem.opponent}, 'Game #' + o.packedGame);
		link.addEventListener('click', function(e) {
			e.preventDefault();

			currentGame = copyGame(o.game);
			handleGameEdit(true);
		});
		return link;
	}

	if ('error' in data) {
		addEvent('💥', 'Fatal error: ' + data.error);
		document.getElementById('summary').replaceChildren(node('DIV', {}, [node('B', {}, 'Summary:'), ' ', 'Error, please see below.']));
		return;
	}
	if ('validationError' in data) {
		addEvent('💥', 'Invalid game: ' + data.validationError.message);
		for (let id of data.validationError.ids) {
			let e = document.getElementById('slot-' + id);
			e.classList.add('error');
			e.style.fill = '#faa';
		}
		document.getElementById('summary').replaceChildren(node('DIV', {}, [node('B', {}, 'Summary:'), ' ', 'Error, please see below.']));
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
					 event.choice.score);
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
				if ('selectedOptionIndex' in event.choice && i == event.choice.selectedOptionIndex)
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
					queryProblem(problem);
				});
				addEvent('➡️', label, option.outcome);
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

	document.getElementById('summary').replaceChildren(node(
		'DIV', {}, [
			node('B', {}, 'Summary:'),
			' ',
		].concat((function() {
			if (data.events.length < 2 || !('start' in data.events[0]))
				return ['Failed to summarize results (unrecognized events).'];
			if ('choice' in data.events[1] && data.events[1].choice.mode === 'best') {
				let bestScore = data.events[1].choice.score;
				let bestOptions = [];
				for (let option of data.events[1].choice.options)
					if (option.outcome === bestScore)
						bestOptions.push(option);
				if (!bestOptions.length)
					return ['Failed to summarize results (no options).'];
				if (bestOptions.length == data.events[1].choice.options.length)
					return [
						"It's your turn, however, at this point, your choice ", node('B', {}, "does not matter"), ". ",
						"No matter what you do now, you have a ", node('B', {}, winPercentFormatter.format(bestScore)), " chance to win."
					];
				else {
					const interleave = (arr, thing) => [].concat(...arr.map(n => [n, thing])).slice(0, -1);
					return [
						"It's your turn. For the best outcome (", node('B', {}, winPercentFormatter.format(bestScore)), "), you should ",
					].concat(interleave(bestOptions.map(option => node('B', {}, option.description)), ' or ')).concat(["."]);
				}
			} else {
				return ["It is currently not your turn, but in this situation, you have a ", node('B', {}, winPercentFormatter.format(data.events[0].start)), " chance to win."];
			}
		})()),
	));
}

let stateVersion = 0;

function queryProblem(problem, delay, noSave) {
	let requestVersion = ++stateVersion;

	if (delay === undefined)
		delay = 0;
	
	currentGame = 'game' in problem ? copyGame(problem.game) : problem.packedGame;
	showGame(currentGame);

	document.getElementById('opponent').value = 'opponent' in problem ? problem.opponent : 'game';

	setTimeout(function() {
		if (requestVersion != stateVersion)
			return; // outdated

		// const state = save();
		// const hash = '#' + state;
		// if (hash != window.location.hash)
		// 	window.location = hash;  // Push state

		document.body.classList.toggle('loading', true);

		fetch('websolver.php', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
			},
			body: JSON.stringify(problem),
		})
		.then((response) => response.json())
		.then((data) => {
			if (requestVersion != stateVersion)
				return; // outdated
			if ('game' in data) {
				currentGame = copyGame(data.game);
				showGame(currentGame);
			}
			addAnalysis(problem, data);
			if ('game' in data && 'packedGame' in data) {
				problem.game = data.game;
				problem.packedGame = data.packedGame;
				if (noSave)
					window.history.replaceState(problem, '', '#' + serialize(problem));
				else
					window.history.pushState(problem, '', '#' + serialize(problem));
			}
			document.body.classList.toggle('loading', false);
		})
		.catch((error) => {
			if (requestVersion != stateVersion)
				return; // outdated
			console.log(error);
			document.body.classList.toggle('loading', false);
			// document.getElementById('status-error').style.display = 'flex';
			document.getElementById('summary').textContent = 'Error: ' + error;
		});
	}, delay);
}

function serialize(problem) {
	let result = problem.packedGame + '/' + problem.opponent;
	if ('decisions' in problem)
		result += '/' + problem.decisions.map(n => n.toString()).join(',');
	return result;
}

function deserialize(hash) {
	let parts = hash.split('/');
	let result = {};
	if (parts.length > 0)
		result.packedGame = parts[0];
	if (parts.length > 1)
		result.opponent = parts[1];
	else
		result.opponent = 'game';
	if (parts.length > 2)
		result.decisions = parts[2].split(',').map(parseInt);
	return result;
}

window.addEventListener('popstate', function(e) {
	let problem;
	if (e.state !== null)
		problem = e.state;
	else if (window.location.hash.length > 1)
		problem = deserialize(window.location.hash.substr(1));
	else
		return;
	loadProblem(problem);
});

// Replaces the current history state. Use after navigation.
function loadProblem(problem) {
	queryProblem(problem, 0, true);
}

// Use this for interactive edits. It creates a new problem, with no decisions.
function handleGameEdit(now) {
	// for (const id of ['status-badinput', 'status-loading', 'status-nodie', 'status-error', 'result-0', 'result-1', 'result-2', 'opp-move-0', 'opp-move-1', 'opp-move-2'])
	// 	document.getElementById(id).style.display = 'none';

	const problem = {
		opponent: document.getElementById('opponent').value,
		[typeof currentGame === 'string' ? 'packedGame' : 'game']: currentGame
	};
	queryProblem(problem, now ? 0 : 500);
}

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

		function cycleValue(game, indexUpdateFun) {
			let oldValue = getValue(game);
			let oldValueIndex = values.indexOf(oldValue);
			let newValueIndex = indexUpdateFun(oldValueIndex);
			newValueIndex = (newValueIndex + values.length) % values.length;
			let newValue = values[newValueIndex];
			setValue(game, newValue);

			handleGameEdit();
		}

		slotNode.addEventListener('mousedown', function(event) {
			if (event.button == 0) {
				cycleValue(currentGame, index => index + 1);
				event.preventDefault();
			}
		});
		slotNode.addEventListener('wheel', function(event) {
			cycleValue(currentGame, index => index + Math.sign(event.deltaX + event.deltaY));
			event.preventDefault();
		});
		slotNode.addEventListener('contextmenu', function(event) {
			cycleValue(currentGame, index => 0);
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

		resetGameFuncs.push((game) => {
			cycleValue(game, index => 0);
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

	document.getElementById('button-flip').addEventListener('click', function(e) {
		e.preventDefault();
		flipBoard();
		handleGameEdit(true);
	});

	document.getElementById('button-reset').addEventListener('click', function(e) {
		e.preventDefault();
		resetBoard();
		handleGameEdit(true);
	});

	document.getElementById('opponent').addEventListener('change', function(e) {
		e.preventDefault();
		handleGameEdit(true);
	});

	let problem = null;
	if (window.location.hash.length > 1) {
		try {
			problem = deserialize(window.location.hash.substr(1));
		} catch (e) {
			console.log(e);
		}
	}
	if (!problem)
		problem = {
			game: defaultGame,
			opponent: 'game',
		};
	loadProblem(problem);

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

	var helpVisible = false;
	document.getElementById('button-help').addEventListener('click', function(e) {
		e.preventDefault();
		helpVisible = !helpVisible;
		document.body.classList.toggle('help-visible', helpVisible);
		document.querySelector('#button-help text').textContent = helpVisible ? '❌' : 'ℹ️';
	});
});
