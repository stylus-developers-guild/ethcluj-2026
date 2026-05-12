const form = document.getElementById("chat-form");
const input = document.getElementById("chat-input");
const messages = document.getElementById("chat-messages");
const article = document.getElementById("page-content");
const panel = document.getElementById("chat-panel");

const panelStorageKey = "chat-panel-open";
const historyStorageKey = `chat-history:${window.location.pathname}`;
const API_KEY = "arb_3773a4165dc5bb832c724a57672f808b";
const API_URL = "https://arbuilder.app/api/v1/chat/completions";

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

/* ── API key (hardcoded) ── */

function getApiKey() {
	return API_KEY;
}

/* ── OpenAI chat completions via fetch ── */

function buildSystemPrompt(sections) {
	const sectionList = sections
		.map((s) => `## ${s.title} [id=${s.id}]\n${s.text}`)
		.join("\n\n---\n\n");

	return `You are a helpful assistant embedded in the Arbitrum Workshop blog. ` +
		`Answer the user's question using ONLY the page content provided below. ` +
		`If the answer is not in the content, say so honestly.\n\n` +
		`After your answer, output a JSON array of relevant section links on a new line ` +
		`prefixed with "SECTIONS:" — each item must have "id" and "title" fields matching ` +
		`the section headers below. If no sections are especially relevant, output "SECTIONS: []".\n\n` +
		`Page: ${document.title}\n` +
		`URL: ${window.location.href}\n\n` +
		`--- PAGE CONTENT ---\n\n${sectionList}`;
}

function parseAssistantResponse(text) {
	const sectionsMatch = text.match(/SECTIONS:\s*(\[.*\])/s);
	let links = [];
	let answer = text;

	if (sectionsMatch) {
		try {
			links = JSON.parse(sectionsMatch[1]);
		} catch (_) {
			links = [];
		}
		answer = text.slice(0, sectionsMatch.index).trim();
	}

	return { answer, links };
}

async function askPage(question) {
	const sections = extractSections(article);
	const systemPrompt = buildSystemPrompt(sections);

	const response = await fetch(API_URL, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			"Authorization": `Bearer ${API_KEY}`
		},
		body: JSON.stringify({
			model: "gpt-4.1-nano",
			messages: [
				{ role: "system", content: systemPrompt },
				{ role: "user", content: question }
			],
			temperature: 0.3,
			max_tokens: 1024
		})
	});

	if (!response.ok) {
		let message = `HTTP ${response.status}`;
		try {
			const err = await response.json();
			if (err && err.error && err.error.message) message = err.error.message;
		} catch (_) {}

		throw new Error(message);
	}

	const data = await response.json();
	const raw = data.choices?.[0]?.message?.content || "No answer returned.";
	return parseAssistantResponse(raw);
}

/* ── Init ── */

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

	// Show a thinking indicator
	const thinking = document.createElement("article");
	thinking.className = "chat-msg chat-thinking";
	thinking.innerHTML = "<h3>Bot</h3><p>Thinking...</p>";
	messages.appendChild(thinking);
	messages.scrollTop = messages.scrollHeight;

	try {
		const result = await askPage(question);
		thinking.remove();
		addMessage("Bot", result.answer || "No answer returned.", result.links || []);
	} catch (err) {
		thinking.remove();
		addMessage("Bot", `Error: ${err.message}`);
	}
});
