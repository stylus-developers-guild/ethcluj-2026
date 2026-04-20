const form = document.getElementById("chat-form");
const input = document.getElementById("chat-input");
const messages = document.getElementById("chat-messages");
const article = document.getElementById("page-content");
const panel = document.getElementById("chat-panel");

const panelStorageKey = "chat-panel-open";
const historyStorageKey = `chat-history:${window.location.pathname}`;

function slugify(text) {
	return String(text)
		.toLowerCase()
		.trim()
		.replace(/[^\w\s-]/g, "")
		.replace(/\s+/g, "-")
		.replace(/-+/g, "-");
}

function ensureHeadingIds(root) {
	if (!root) return;
	const headings = root.querySelectorAll("h1, h2, h3, h4, h5, h6");
	const used = new Set();

	for (const heading of headings) {
		let id = heading.id && heading.id.trim();
		if (!id) {
			id = slugify(heading.textContent || "section");
		}
		if (!id) id = "section";

		let candidate = id;
		let i = 2;
		while (used.has(candidate) || document.getElementById(candidate)) {
			if (heading.id === candidate) break;
			candidate = `${id}-${i}`;
			i += 1;
		}

		heading.id = candidate;
		used.add(candidate);
	}
}

function getHeadingLevel(el) {
	return Number(el.tagName.slice(1));
}

function extractSections(root) {
	if (!root) {
		return [{
			id: "page",
			title: document.title || "Page",
			level: 1,
			text: document.body.innerText.trim()
		}];
	}

	ensureHeadingIds(root);

	const nodes = Array.from(root.children);
	const headings = nodes.filter((node) => /^H[1-6]$/.test(node.tagName));

	if (headings.length === 0) {
		return [{
			id: "page",
			title: document.title || "Page",
			level: 1,
			text: root.innerText.trim()
		}];
	}

	const sections = [];

	for (let i = 0; i < headings.length; i += 1) {
		const heading = headings[i];
		const startIndex = nodes.indexOf(heading);
		const nextHeading = headings[i + 1];
		const endIndex = nextHeading ? nodes.indexOf(nextHeading) : nodes.length;

		const chunkNodes = nodes.slice(startIndex, endIndex);
		const text = chunkNodes
			.map((node) => node.innerText || "")
			.join("\n\n")
			.trim();

		sections.push({
			id: heading.id,
			title: heading.textContent.trim(),
			level: getHeadingLevel(heading),
			text
		});
	}

	return sections;
}

function renderSectionLinks(links) {
	if (!Array.isArray(links) || links.length === 0) {
		return null;
	}

	const nav = document.createElement("nav");
	nav.setAttribute("aria-label", "Relevant sections");

	const p = document.createElement("p");
	p.textContent = "Relevant sections:";
	nav.appendChild(p);

	const list = document.createElement("ul");

	for (const link of links) {
		if (!link || !link.id || !link.title) continue;

		const li = document.createElement("li");
		const a = document.createElement("a");
		a.href = `#${link.id}`;
		a.textContent = link.title;
		a.addEventListener("click", (e) => {
			e.preventDefault();
			const target = document.getElementById(link.id);
			if (target) {
				target.scrollIntoView({ behavior: "smooth", block: "start" });
				history.replaceState(null, "", `#${link.id}`);
			}
		});
		li.appendChild(a);
		list.appendChild(li);
	}

	if (list.children.length === 0) return null;

	nav.appendChild(list);
	return nav;
}

function addMessage(role, text, links = []) {
	const articleEl = document.createElement("article");
	const heading = document.createElement("h3");
	const body = document.createElement("p");

	heading.textContent = role;
	body.textContent = text;

	articleEl.className = "chat-msg";
	articleEl.appendChild(heading);
	articleEl.appendChild(body);

	const sectionNav = renderSectionLinks(links);
	if (sectionNav) {
		articleEl.appendChild(sectionNav);
	}

	messages.appendChild(articleEl);
	messages.scrollTop = messages.scrollHeight;
	saveHistory();
}

function saveHistory() {
	if (!messages) return;
	localStorage.setItem(historyStorageKey, messages.innerHTML);
}

function restoreHistory() {
	if (!messages) return;
	const saved = localStorage.getItem(historyStorageKey);
	if (saved) {
		messages.innerHTML = saved;

		const anchors = messages.querySelectorAll('a[href^="#"]');
		for (const a of anchors) {
			a.addEventListener("click", (e) => {
				e.preventDefault();
				const id = a.getAttribute("href").slice(1);
				const target = document.getElementById(id);
				if (target) {
					target.scrollIntoView({ behavior: "smooth", block: "start" });
					history.replaceState(null, "", `#${id}`);
				}
			});
		}

		messages.scrollTop = messages.scrollHeight;
	}
}

function setupPanelPersistence() {
	if (!panel) return;

	const saved = localStorage.getItem(panelStorageKey);
	if (saved === "true") panel.open = true;
	if (saved === "false") panel.open = false;

	panel.addEventListener("toggle", () => {
		localStorage.setItem(panelStorageKey, String(panel.open));
	});
}

async function askPage(question) {
	const sections = extractSections(article);
	const pageText = article ? article.innerText.trim() : document.body.innerText.trim();

	const response = await fetch("/ask", {
		method: "POST",
		headers: {
			"Content-Type": "application/json"
		},
		body: JSON.stringify({
			question,
			page: {
				title: document.title,
				path: window.location.pathname,
				url: window.location.href,
				text: pageText,
				sections
			}
		})
	});

	if (!response.ok) {
		let message = `HTTP ${response.status}`;
		try {
			const err = await response.json();
			if (err && err.error) message = err.error;
		} catch (_) {}
		throw new Error(message);
	}

	return response.json();
}

setupPanelPersistence();
restoreHistory();

form.addEventListener("submit", async (e) => {
	e.preventDefault();

	const question = input.value.trim();
	if (!question) return;

	addMessage("You", question);
	input.value = "";

	if (panel && !panel.open) {
		panel.open = true;
	}

	try {
		const result = await askPage(question);
		addMessage("Bot", result.answer || "No answer returned.", result.links || []);
	} catch (err) {
		addMessage("Bot", `Error: ${err.message}`);
	}
});
