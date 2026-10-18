.pragma library

// Shared command-bar search and result shaping. Keep this independent of QML
// objects so the popup stays focused on interaction and presentation.

const schemeRegex = /^[a-z][a-z0-9+.-]*:\/\//i;
const whitespaceRegex = /\s/;
const domainRegex = /^[^.\s]+\.[^\s]+$/;
const localhostRegex = /^localhost(:\d+)?(\/|$)/i;
const schemePrefixRegex = /^([a-z][a-z0-9+.-]*):/i;
const stripSchemeRegex = /^[a-z][a-z0-9+.-]*:\/\/(www\.)?/i;
const wordBoundaryRegex = /[\s\/._\-:]/;

function looksLikeUrl(text) {
    if (schemeRegex.test(text))
        return true;
    return !whitespaceRegex.test(text) && (domainRegex.test(text) || localhostRegex.test(text));
}

function isInternalUrl(url, schemes) {
    if (whitespaceRegex.test(url))
        return false;
    const match = schemePrefixRegex.exec(url);
    return match !== null && schemes.indexOf(match[1].toLowerCase()) !== -1;
}

function stripScheme(url) {
    return url.replace(stripSchemeRegex, "");
}

function matchScore(haystack, query) {
    const value = String(haystack).toLowerCase();
    const index = value.indexOf(query);
    if (index < 0)
        return 0;
    if (index === 0)
        return 3;
    return wordBoundaryRegex.test(value.charAt(index - 1)) ? 2 : 1;
}

function makeRow(kind, key, fields) {
    return Object.assign({
        key: key,
        kind: kind,
        title: "",
        subtitle: "",
        dest: "",
        url: "",
        iconUrl: "",
        icon: "",
        tabIndex: -1,
        actionIndex: -1
    }, fields);
}

function sameRow(a, b) {
    return a.kind === b.kind && a.title === b.title && a.subtitle === b.subtitle
        && a.dest === b.dest && a.url === b.url && a.iconUrl === b.iconUrl
        && a.icon === b.icon && a.tabIndex === b.tabIndex && a.actionIndex === b.actionIndex;
}

function compatible(list, query) {
    return list.filter(item => item.text.toLowerCase().includes(query)
                               || (item.url !== "" && item.url.toLowerCase().includes(query)));
}

function buildResults(context) {
    const text = context.text.trim();
    if (text === "" || !context.queryActive)
        return [];
    const query = text.toLowerCase();
    const go = makeRow("go", "go", {
        title: text,
        subtitle: looksLikeUrl(text) ? "Open" : "Search " + context.searchEngineName,
        dest: text
    });

    const actionHits = [];
    for (let i = 0; i < context.quickActions.length; ++i) {
        const score = matchScore(context.quickActions[i].label, query);
        if (score > 0)
            actionHits.push({ score: score, order: i });
    }
    actionHits.sort((a, b) => b.score - a.score || a.order - b.order);
    const actionRows = actionHits.slice(0, 2).map(hit => {
        const action = context.quickActions[hit.order];
        return makeRow("action", "action:" + action.label, {
            title: String(action.label), subtitle: "Action", icon: String(action.icon || ""), actionIndex: hit.order
        });
    });

    const tabHits = [];
    const tabUrls = {};
    for (let i = context.tabs.count - 1; i >= 0; --i) {
        if (context.mode === "edit" && i === context.tabs.activeIndex)
            continue;
        const tab = context.tabs.itemAt(i);
        if (!tab)
            continue;
        const url = tab.url.toString();
        if (isInternalUrl(url, context.internalSchemes))
            continue;
        const title = String(tab.title || "");
        const score = Math.max(matchScore(title, query), matchScore(stripScheme(url), query));
        if (score > 0)
            tabHits.push({ score: score, order: tabHits.length, index: i, title: title, url: url, iconUrl: tab.iconUrl.toString() });
    }
    tabHits.sort((a, b) => b.score - a.score || a.order - b.order);
    const tabRows = tabHits.slice(0, 3).map(hit => {
        tabUrls[hit.url] = true;
        return makeRow("tab", "tab:" + hit.index + ":" + hit.url, {
            title: hit.title, subtitle: "Switch to Tab", url: hit.url, iconUrl: hit.iconUrl, tabIndex: hit.index
        });
    });

    const bookmarkRows = [];
    const searchRows = [];
    const seen = {};
    for (const suggestion of context.suggestions) {
        if (suggestion.isBookmark) {
            if (isInternalUrl(suggestion.url, context.internalSchemes) || tabUrls[suggestion.url])
                continue;
            bookmarkRows.push(makeRow("bookmark", "bookmark:" + suggestion.url, {
                title: suggestion.text, subtitle: suggestion.url, dest: suggestion.url, url: suggestion.url
            }));
        } else {
            const key = suggestion.text.toLowerCase();
            if (key === query || seen[key] || isInternalUrl(suggestion.text, context.internalSchemes))
                continue;
            seen[key] = true;
            searchRows.push(makeRow("suggest", "suggest:" + key, { title: suggestion.text, dest: suggestion.text }));
        }
    }

    const local = actionRows.concat(tabRows, bookmarkRows.slice(0, 2)).slice(0, context.maxRows - 3);
    const suggestions = searchRows.slice(0, context.maxRows - 1 - local.length);
    return [go].concat(local, suggestions);
}
