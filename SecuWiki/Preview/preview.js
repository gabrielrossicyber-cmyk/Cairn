// Rendu Markdown de Cairn : markdown-it + highlight.js + Mermaid, 100 % local.
(function () {
  // Mode sombre : suit l'apparence de l'app (WKWebView transmet prefers-color-scheme).
  const darkQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function isDark() { return !!(darkQuery && darkQuery.matches); }

  function initMermaid() {
    if (window.mermaid) {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: isDark() ? 'dark' : 'default' });
    }
  }
  initMermaid();

  // Dernier rendu : permet de redessiner (schémas compris) quand on passe en clair / sombre.
  let lastRender = null;
  if (darkQuery && darkQuery.addEventListener) {
    darkQuery.addEventListener('change', function () {
      initMermaid();
      if (lastRender) window.renderMarkdown(lastRender.source, false, lastRender.context);
    });
  }

  const md = window.markdownit({
    html: false,       // HTML brut désactivé : un contenu collé ne peut pas injecter de script (XSS)
    linkify: true,     // les URL deviennent des liens
    breaks: true,      // un retour à la ligne dans l'éditeur = un retour à la ligne à l'affichage
    typographer: false,
    highlight: function (code, lang) {
      // ```mermaid -> schéma (dessiné ensuite par renderMermaid)
      if (lang === 'mermaid') {
        return '<pre class="mermaid">' + md.utils.escapeHtml(code) + '</pre>';
      }
      // ```flux -> « A > B > C » converti en flowchart Mermaid
      if (lang === 'flux') {
        return '<pre class="mermaid">' + md.utils.escapeHtml(fluxToMermaid(code)) + '</pre>';
      }
      if (lang && window.hljs && hljs.getLanguage(lang)) {
        try {
          return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
        } catch (e) { /* on retombe sur le rendu par défaut */ }
      }
      return ''; // markdown-it échappe alors le code lui-même
    }
  });

  // Chaque bloc garde le numéro de sa ligne dans le texte (data-line) :
  // sert au défilement synchronisé éditeur -> aperçu.
  md.core.ruler.push('source_lines', function (state) {
    state.tokens.forEach(function (token) {
      if (token.map && (token.nesting === 1 || token.type === 'fence')) {
        token.attrSet('data-line', String(token.map[0]));
      }
    });
  });

  // Même normalisation que Swift : sans accents, en minuscules.
  function normalize(text) {
    return text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
  }

  // Cmd+C sur une sélection qui contient des « 🔑 NOM » : on copie avec {{secret:NOM}},
  // et l'app remplace par les valeurs du Trousseau (presse-papiers effacé après 60 s).
  document.addEventListener('copy', function (event) {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return;
    const fragment = selection.getRangeAt(0).cloneContents();
    const names = [];
    fragment.querySelectorAll('.secret:not(.secret-missing)').forEach(function (pill) {
      if (pill.dataset.secret && names.indexOf(pill.dataset.secret) === -1) names.push(pill.dataset.secret);
    });
    if (!names.length || !window.webkit || !window.webkit.messageHandlers.copy) return;
    let text = selection.toString();
    names.forEach(function (name) {
      text = text.split('🔑 ' + name).join('{{secret:' + name + '}}');
    });
    event.preventDefault();
    window.webkit.messageHandlers.copy.postMessage(text);
  });

  // Bouton « Copier » sur chaque bloc de code (sauf les schémas).
  function addCopyButtons(root) {
    root.querySelectorAll('pre:not(.mermaid)').forEach(function (pre) {
      // Langage du bloc (bash, powershell…) affiché discrètement en haut à droite.
      const codeEl = pre.querySelector('code');
      const langMatch = codeEl && /language-([\w+#-]+)/.exec(codeEl.className);
      if (langMatch) {
        const badge = document.createElement('span');
        badge.className = 'code-lang';
        badge.textContent = langMatch[1];
        pre.appendChild(badge);
      }
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'copy-btn';
      button.textContent = 'Copier';
      button.addEventListener('click', function () {
        // Les secrets redeviennent {{secret:NOM}} : l'app insère la valeur du Trousseau à la copie.
        const source = (pre.querySelector('code') || pre).cloneNode(true);
        source.querySelectorAll('.secret').forEach(function (pill) {
          pill.replaceWith('{{secret:' + pill.dataset.secret + '}}');
        });
        source.querySelectorAll('.copy-btn, .code-lang').forEach(function (el) { el.remove(); });
        const text = source.textContent.replace(/\n$/, '');
        window.webkit.messageHandlers.copy.postMessage(text);
        button.textContent = 'Copié ✓';
        setTimeout(function () { button.textContent = 'Copier'; }, 1500);
      });
      pre.appendChild(button);
    });
  }

  // "- [ ] tâche" / "- [x] tâche" -> case à cocher.
  // Aperçu principal : cliquable, l'app coche / décoche la ligne correspondante du texte.
  function renderTaskLists(root, interactive) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.task;
    const clickable = interactive && !!handler;
    let index = 0;
    root.querySelectorAll('li').forEach(function (li) {
      let first = li.firstChild;
      if (first && first.nodeType === 1 && first.tagName === 'P') first = first.firstChild;
      if (!first || first.nodeType !== 3) return;
      const match = first.nodeValue.match(/^\[([ xX])\]\s+/);
      if (!match) return;
      first.nodeValue = first.nodeValue.slice(match[0].length);
      const box = document.createElement('input');
      box.type = 'checkbox';
      box.disabled = !clickable;
      box.checked = match[1] !== ' ';
      const taskIndex = index++;
      if (clickable) {
        box.addEventListener('change', function () { handler.postMessage(taskIndex); });
      }
      first.parentNode.insertBefore(box, first);
      li.classList.add('task-item');
    });
  }

  // Encadrés : "> [!NOTE]" (bleu), "> [!TIP]" (vert), "> [!IMPORTANT]" (violet),
  // "> [!WARNING]" (orange), "> [!CAUTION]" (rouge), "> [!REPONSE]" (réponse masquée).
  const CALLOUTS = {
    NOTE: ['note', 'Information'], INFO: ['note', 'Information'], INFORMATION: ['note', 'Information'],
    TIP: ['tip', 'Astuce'], ASTUCE: ['tip', 'Astuce'],
    IMPORTANT: ['important', 'Important'],
    WARNING: ['warning', 'Avertissement'], AVERTISSEMENT: ['warning', 'Avertissement'],
    CAUTION: ['caution', 'Attention'], ATTENTION: ['caution', 'Attention'], DANGER: ['caution', 'Attention'],
    // Encadrés repliables : [classe, titre replié, titre déplié]
    REPONSE: ['answer', 'Afficher la réponse', 'Masquer la réponse'],
    ANSWER: ['answer', 'Afficher la réponse', 'Masquer la réponse'],
    SOLUTION: ['answer', 'Afficher la réponse', 'Masquer la réponse'],
    EXTRAIT: ['extract', 'Afficher le texte extrait du document', 'Masquer le texte extrait']
  };

  function renderCallouts(root) {
    root.querySelectorAll('blockquote').forEach(function (quote) {
      const paragraph = quote.firstElementChild;
      if (!paragraph || paragraph.tagName !== 'P') return;
      const first = paragraph.firstChild;
      if (!first || first.nodeType !== 3) return;
      const match = first.nodeValue.match(/^\s*\[!([^\]\s]+)\][ \t]*\n?/);
      if (!match) return;
      const key = match[1].normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase();
      const type = CALLOUTS[key];
      if (!type) return;

      first.nodeValue = first.nodeValue.slice(match[0].length);
      // Retire le saut de ligne (<br>) qui suivait le marqueur [!TYPE].
      if (!first.nodeValue.trim() && first.nextSibling && first.nextSibling.nodeName === 'BR') {
        paragraph.removeChild(first.nextSibling);
        first.nodeValue = '';
      }
      if (!paragraph.textContent.trim() && paragraph.querySelectorAll('img').length === 0) quote.removeChild(paragraph);

      quote.classList.add('callout', 'callout-' + type[0]);
      const title = document.createElement('div');
      title.className = 'callout-title';
      title.textContent = type[1];

      if (type[2]) {
        // Encadré repliable (réponse de révision, texte extrait d'un PDF) : fermé jusqu'au clic.
        const body = document.createElement('div');
        body.className = 'answer-body';
        while (quote.firstChild) body.appendChild(quote.firstChild);
        quote.appendChild(title);
        quote.appendChild(body);
        title.addEventListener('click', function () {
          const open = quote.classList.toggle('open');
          title.textContent = open ? type[2] : type[1];
        });
      } else {
        quote.insertBefore(title, quote.firstChild);
      }
    });
  }

  // Adresse d'un fichier du wiki (relatif au dossier de la page) pour l'aperçu.
  function assetURL(path, base) {
    if (/^[a-z][a-z0-9+.-]*:/i.test(path)) return path;
    const full = path.charAt(0) === '/' ? path : (base || '') + '/' + path;
    return 'secuwiki-asset://' + encodeURI(full);
  }

  // ![[assets/doc.pdf]] -> PDF affiché dans la page ; ![[assets/image.png]] -> image.
  function makeEmbed(target, base) {
    if (/\.pdf$/i.test(target)) {
      const wrapper = document.createElement('span');
      wrapper.className = 'pdf-embed';
      const frame = document.createElement('iframe');
      frame.src = assetURL(target, base);
      frame.title = target;
      const open = document.createElement('a');
      open.className = 'pdf-open';
      open.href = assetURL(target, base);
      open.textContent = 'Ouvrir le PDF dans Aperçu';
      wrapper.appendChild(frame);
      wrapper.appendChild(open);
      return wrapper;
    }
    if (/\.(png|jpe?g|gif|webp|svg|heic|bmp|tiff)$/i.test(target)) {
      const img = document.createElement('img');
      img.src = assetURL(target, base);
      img.alt = target;
      return img;
    }
    return null;
  }

  // [[Nom de page]] ou [[Nom de page|texte affiché]] -> lien interne. ![[fichier]] -> fichier intégré.
  function renderWikiLinks(root, pages, base) {
    const known = new Set(pages || []);
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        return node.parentElement && node.parentElement.closest('pre, code, a')
          ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }
    });
    const nodes = [];
    while (walker.nextNode()) {
      if (walker.currentNode.nodeValue.indexOf('[[') !== -1) nodes.push(walker.currentNode);
    }
    nodes.forEach(function (node) {
      const text = node.nodeValue;
      const pattern = /(!?)\[\[([^\]|\n]+)(?:\|([^\]\n]+))?\]\]/g;
      const fragment = document.createDocumentFragment();
      let last = 0;
      let match;
      while ((match = pattern.exec(text))) {
        fragment.appendChild(document.createTextNode(text.slice(last, match.index)));
        const target = match[2].trim();
        if (match[1] === '!') {
          const embed = makeEmbed(target, base);
          if (embed) {
            fragment.appendChild(embed);
            last = pattern.lastIndex;
            continue;
          }
        }
        const exists = known.has(normalize(target));
        const link = document.createElement('a');
        link.textContent = (match[3] || match[2]).trim();
        link.className = exists ? 'wikilink' : 'wikilink missing';
        link.title = exists ? target : 'Page inexistante : clique pour la créer';
        link.href = 'secuwiki://page?name=' + encodeURIComponent(target);
        fragment.appendChild(link);
        last = pattern.lastIndex;
      }
      fragment.appendChild(document.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(fragment, node);
    });
  }

  // {{secret:NOM}} -> « 🔑 NOM » (la valeur n'arrive jamais dans la page ; elle est insérée à la copie).
  const secretPattern = /\{\{\s*secret:([A-Za-z0-9_-]+)\s*\}\}/g;
  function renderSecrets(root, known) {
    const names = new Set(known || []);
    function pill(name) {
      const span = document.createElement('span');
      const present = names.has(name);
      span.className = present ? 'secret' : 'secret secret-missing';
      span.dataset.secret = name;
      span.textContent = '🔑 ' + name;
      span.title = present
        ? 'Secret « ' + name + ' » (Trousseau) : clique pour copier sa valeur (effacée du presse-papiers après 60 s)'
        : 'Secret « ' + name + ' » absent du Trousseau : ajoute-le dans Réglages › Secrets';
      if (present) {
        // Clic : copie la valeur seule (l'app la lit dans le Trousseau ; elle n'entre jamais dans la page).
        span.addEventListener('click', function (event) {
          event.preventDefault();
          event.stopPropagation();
          window.webkit.messageHandlers.copy.postMessage('{{secret:' + name + '}}');
          span.textContent = '✓ copié';
          span.classList.add('secret-copied');
          setTimeout(function () {
            span.textContent = '🔑 ' + name;
            span.classList.remove('secret-copied');
          }, 1200);
        });
      }
      return span;
    }
    function fill(container, text) {
      let last = 0;
      let match;
      secretPattern.lastIndex = 0;
      while ((match = secretPattern.exec(text))) {
        container.appendChild(document.createTextNode(text.slice(last, match.index)));
        container.appendChild(pill(match[1]));
        last = secretPattern.lastIndex;
      }
      container.appendChild(document.createTextNode(text.slice(last)));
    }
    // Code : la coloration découpe le texte en morceaux ; on reconstruit le bloc en texte simple.
    root.querySelectorAll('code').forEach(function (code) {
      const text = code.textContent;
      secretPattern.lastIndex = 0;
      if (!secretPattern.test(text)) return;
      code.textContent = '';
      fill(code, text);
    });
    // Texte normal
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        return node.parentElement && node.parentElement.closest('code, .secret')
          ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }
    });
    const nodes = [];
    while (walker.nextNode()) {
      if (walker.currentNode.nodeValue.indexOf('{{') !== -1) nodes.push(walker.currentNode);
    }
    nodes.forEach(function (node) {
      secretPattern.lastIndex = 0;
      if (!secretPattern.test(node.nodeValue)) return;
      const fragment = document.createDocumentFragment();
      fill(fragment, node.nodeValue);
      node.parentNode.replaceChild(fragment, node);
    });
  }

  // #tag dans le texte -> pastille cliquable (ouvre la recherche filtrée sur ce tag).
  // Même règle que Swift (MarkdownPage.inlineTagPattern) : pas dans le code, pas après une lettre, « / », « ( »…
  const tagPattern = /(?<![\p{L}\p{N}_#\/&=?.:(\-])#(\p{L}[\p{L}\p{N}_\-]*)/gu;
  function renderTags(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        return node.parentElement && node.parentElement.closest('pre, code, a')
          ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      }
    });
    const nodes = [];
    while (walker.nextNode()) {
      if (walker.currentNode.nodeValue.indexOf('#') !== -1) nodes.push(walker.currentNode);
    }
    nodes.forEach(function (node) {
      const text = node.nodeValue;
      tagPattern.lastIndex = 0;
      if (!tagPattern.test(text)) return;
      tagPattern.lastIndex = 0;
      const fragment = document.createDocumentFragment();
      let last = 0;
      let match;
      while ((match = tagPattern.exec(text))) {
        fragment.appendChild(document.createTextNode(text.slice(last, match.index)));
        const link = document.createElement('a');
        link.className = 'tag';
        link.textContent = '#' + match[1];
        link.title = 'Pages avec #' + match[1];
        link.href = 'secuwiki-tag://tag?name=' + encodeURIComponent(match[1]);
        fragment.appendChild(link);
        last = tagPattern.lastIndex;
      }
      fragment.appendChild(document.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(fragment, node);
    });
  }

  // Images relatives (assets/capture.png) -> servies par l'app depuis le dossier de la page.
  function resolveImages(root, base) {
    if (!base) return;
    root.querySelectorAll('img').forEach(function (img) {
      const src = img.getAttribute('src') || '';
      if (!src || /^[a-z][a-z0-9+.-]*:/i.test(src)) return; // http:, data:… : on n'y touche pas
      const path = src.charAt(0) === '/' ? src : encodeURI(base) + '/' + src;
      img.src = 'secuwiki-asset://' + path;
    });
  }

  // ---------- Flux simplifié ----------
  //
  //   ```flux
  //   Préparer > Détecter > Contenir > Éradiquer
  //   Détecter > Faux positif ? > [oui] Clore
  //   ```
  //
  // - Une ligne = une chaîne d'étapes (séparateurs : >  ->  →  =>).
  // - Le même nom sur plusieurs lignes = la même case : on peut faire des branches.
  // - « ? » à la fin = décision (losange). « (Début) » entre parenthèses = case arrondie.
  // - [texte] devant une étape = étiquette sur la flèche qui y mène.
  // - Une ligne « vertical » = schéma de haut en bas (horizontal par défaut).

  function fluxToMermaid(code) {
    const ids = new Map();
    const nodes = [];
    const edges = [];
    const choices = [];
    let direction = 'LR';

    const quote = function (text) { return '"' + text.replace(/"/g, '#quot;') + '"'; };

    function nodeId(label) {
      const key = label.toLowerCase().replace(/\s+/g, ' ');
      if (ids.has(key)) return ids.get(key);
      const id = 'n' + ids.size;
      ids.set(key, id);
      if (/\?\s*$/.test(label)) {
        nodes.push(id + '{' + quote(label) + '}');
        choices.push(id);
      } else if (/^\(.*\)$/.test(label)) {
        nodes.push(id + '([' + quote(label.slice(1, -1).trim()) + '])');
      } else {
        nodes.push(id + '[' + quote(label) + ']');
      }
      return id;
    }

    code.split('\n').forEach(function (raw) {
      const line = raw.trim();
      if (!line || line.startsWith('%%')) return;
      if (/^(vertical|haut-bas|top-down)$/i.test(line)) { direction = 'TD'; return; }
      if (/^(horizontal|gauche-droite)$/i.test(line)) { direction = 'LR'; return; }

      let previous = null;
      line.split(/\s*(?:-+>|=>|→|>)\s*/).forEach(function (part) {
        const match = part.match(/^\[([^\]]*)\]\s*(.*)$/);
        const edgeLabel = match ? match[1].trim() : '';
        const label = (match ? match[2] : part).trim();
        if (!label) return;
        const id = nodeId(label);
        if (previous) {
          edges.push(previous + (edgeLabel ? ' -->|' + quote(edgeLabel) + '| ' : ' --> ') + id);
        }
        previous = id;
      });
    });

    const lines = ['flowchart ' + direction]
      .concat(nodes, edges)
      .concat(isDark() ? [
        'classDef default fill:#2a2d2c,stroke:#5c6563,color:#e6e3da',
        'classDef choice fill:#1f3530,stroke:#5fb39f,color:#e6e3da'
      ] : [
        'classDef default fill:#f6f7f5,stroke:#a7b0ad,color:#1d2b2e',
        'classDef choice fill:#eaf4f1,stroke:#3e8e7e,color:#1d2b2e'
      ]);
    if (choices.length) lines.push('class ' + choices.join(',') + ' choice');
    return lines.join('\n    ');
  }

  // ---------- Schémas Mermaid ----------
  //
  // Chaque schéma est d'abord vérifié (mermaid.parse) avant d'être dessiné.
  // S'il contient une erreur : encadré clair (ligne fautive + conseil), et pendant la frappe
  // la dernière version correcte reste visible en grisé (pas de clignotement).

  const lastGoodDiagrams = []; // dernier SVG valide, par position du schéma dans la page
  let renderCounter = 0;

  async function renderMermaid(root, autoVertical, newPage) {
    if (newPage) lastGoodDiagrams.length = 0;
    const blocks = Array.prototype.slice.call(root.querySelectorAll('pre.mermaid'));
    if (!blocks.length || !window.mermaid) return;

    for (let i = 0; i < blocks.length; i++) {
      const pre = blocks[i];
      const source = pre.textContent;
      pre.dataset.source = source;
      try {
        if (!svgCache.has(cacheKey(source))) await mermaid.parse(source);
        const svg = await renderSvg(source);
        pre.innerHTML = svg;
        lastGoodDiagrams[i] = svg;
      } catch (error) {
        showDiagramError(pre, source, error, lastGoodDiagrams[i]);
      }
    }
    removeMermaidLeftovers();
    if (autoVertical) await fitLongDiagrams(root);
  }

  // Schémas déjà dessinés (par thème) : en mode côte à côte, taper du texte ne redessine
  // plus tous les schémas de la page à chaque frappe, seulement celui qui a changé.
  const svgCache = new Map();
  function cacheKey(source) { return (isDark() ? 'd' : 'l') + '\u0000' + source; }

  // Dessine un schéma et nettoie les éléments temporaires que Mermaid ajoute à la page.
  async function renderSvg(source) {
    const key = cacheKey(source);
    if (svgCache.has(key)) return svgCache.get(key);
    const id = 'mmd-' + (++renderCounter);
    try {
      const result = await mermaid.render(id, source);
      svgCache.set(key, result.svg);
      if (svgCache.size > 80) svgCache.delete(svgCache.keys().next().value);
      return result.svg;
    } finally {
      const temporary = document.getElementById('d' + id);
      if (temporary) temporary.remove();
      const stray = document.getElementById(id);
      if (stray && !stray.closest('#content')) stray.remove();
    }
  }

  // Mermaid peut laisser des « bombes » d'erreur à la fin de la page : on les supprime.
  function removeMermaidLeftovers() {
    document.querySelectorAll('body > div[id^="dmmd-"], body > svg[id^="mmd-"], body > div[id^="dmermaid"], body > svg[id^="mermaid"]')
      .forEach(function (element) { element.remove(); });
  }

  // Conseil adapté à l'erreur la plus fréquente sur la ligne fautive.
  function diagramHint(line, source) {
    const firstLine = (source.split('\n').find(function (l) { return l.trim() && !l.trim().startsWith('%%'); }) || '').trim();
    const types = /^(flowchart|graph|sequenceDiagram|classDiagram|stateDiagram|stateDiagram-v2|erDiagram|gantt|pie|journey|mindmap|timeline|gitGraph|quadrantChart|requirementDiagram|C4Context|block-beta|sankey-beta|xychart-beta)\b/;
    if (!types.test(firstLine)) {
      return 'La première ligne doit indiquer le type de schéma : flowchart LR, sequenceDiagram, classDiagram, stateDiagram-v2, erDiagram…';
    }
    if (!line) return 'Vérifie la syntaxe autour de cette ligne.';
    const pairs = [['[', ']'], ['(', ')'], ['{', '}']];
    for (let p = 0; p < pairs.length; p++) {
      const opened = line.split(pairs[p][0]).length - 1;
      const closed = line.split(pairs[p][1]).length - 1;
      if (opened !== closed) {
        return 'Un « ' + pairs[p][0] + ' » ou « ' + pairs[p][1] + ' » n\'est pas fermé correctement sur cette ligne.';
      }
    }
    if (/[\])}][^\s;\-~=.:&|>]/.test(line)) {
      return 'Il y a du texte collé juste après un crochet fermant (par ex. « ]D ») : supprime-le, ou ajoute une flèche --> entre les deux éléments.';
    }
    if (/\[[^\]"]*[(){}][^\]]*\]/.test(line)) {
      return 'Les caractères ( ) { } dans un texte doivent être entre guillemets : A["Texte (avec parenthèses)"].';
    }
    if (/-->|---|==>|-\.->/.test(line) && /-->\s*$/.test(line)) {
      return 'La flèche ne pointe vers rien : ajoute un élément après « --> ».';
    }
    return 'Vérifie la syntaxe de cette ligne (flèches -->, crochets, guillemets).';
  }

  function showDiagramError(pre, source, error, previousSvg) {
    const message = String((error && (error.message || error.str)) || error || 'Erreur inconnue');
    const lineMatch = message.match(/line\s+(\d+)/i);
    const rawLineNumber = lineMatch ? Number(lineMatch[1]) : null;
    const lines = source.split('\n');
    let lineNumber = rawLineNumber;
    // Erreur signalée « en fin de texte » : on remonte à la dernière ligne non vide.
    while (lineNumber && lineNumber > 1 && (lines[lineNumber - 1] === undefined || !lines[lineNumber - 1].trim())) {
      lineNumber -= 1;
    }
    const badLine = lineNumber && lines[lineNumber - 1] !== undefined ? lines[lineNumber - 1] : null;

    pre.classList.add('mermaid-error');
    pre.innerHTML = '';

    if (previousSvg) {
      const stale = document.createElement('div');
      stale.className = 'mermaid-stale';
      stale.innerHTML = previousSvg;
      pre.appendChild(stale);
    }

    const box = document.createElement('div');
    box.className = 'diagram-error';

    const title = document.createElement('div');
    title.className = 'diagram-error-title';
    title.textContent = 'Schéma invalide' + (lineNumber ? ' — ligne ' + lineNumber : '');
    box.appendChild(title);

    if (badLine !== null) {
      const code = document.createElement('code');
      code.className = 'diagram-error-line';
      code.textContent = badLine.trim();
      box.appendChild(code);
    }

    const hint = document.createElement('div');
    hint.className = 'diagram-error-hint';
    hint.textContent = diagramHint(badLine, source);
    box.appendChild(hint);

    if (previousSvg) {
      const note = document.createElement('div');
      note.className = 'diagram-error-note';
      note.textContent = 'La dernière version correcte est affichée en grisé.';
      box.appendChild(note);
    }

    const details = document.createElement('details');
    const summary = document.createElement('summary');
    summary.textContent = 'Détail technique';
    const raw = document.createElement('pre');
    raw.textContent = message;
    details.appendChild(summary);
    details.appendChild(raw);
    box.appendChild(details);

    pre.appendChild(box);
  }

  // Réglages > Aperçu / Export : taille du texte, largeur, retours à la ligne, réponses dans le PDF.
  function applySettings(context) {
    const style = document.documentElement.style;
    if (context.fontSize) style.setProperty('--font-size', context.fontSize + 'px');
    style.setProperty('--max-width', context.maxWidth > 0 ? context.maxWidth + 'px' : 'none');
    md.set({ breaks: context.breaks !== false });
    if (document.body) document.body.classList.toggle('hide-answers', context.printAnswers === false);
  }

  // Largeur « réelle » d'un schéma (avant réduction pour tenir dans la page).
  function naturalWidth(svg) {
    const box = svg.viewBox && svg.viewBox.baseVal;
    return box && box.width ? box.width : svg.getBoundingClientRect().width;
  }

  // Un schéma horizontal (LR) trop large devient minuscule : on le redessine de haut en bas (TD),
  // chaque étape passe sous la précédente et le texte reste lisible.
  async function fitLongDiagrams(root) {
    const available = root.clientWidth;
    const pattern = /^(\s*(?:flowchart|graph)\s+)(LR|RL)\b/m;
    for (const pre of Array.prototype.slice.call(root.querySelectorAll('pre.mermaid:not(.mermaid-error)'))) {
      const svg = pre.querySelector('svg');
      const source = pre.dataset.source || '';
      if (!svg || !available || !pattern.test(source)) continue;
      if (naturalWidth(svg) <= available * 1.2) continue;
      try {
        pre.innerHTML = await renderSvg(source.replace(pattern, '$1TD'));
        pre.classList.add('auto-vertical');
      } catch (e) { /* on garde la version horizontale */ }
    }
  }

  // Clic sur un schéma ou une image : affichage en grand (clic ou Échap pour fermer).
  function openLightbox(element) {
    const overlay = document.createElement('div');
    overlay.className = 'lightbox';
    const hint = document.createElement('div');
    hint.className = 'lightbox-hint';
    hint.textContent = 'Clic ou Échap pour fermer';
    const frame = document.createElement('div');
    frame.className = 'lightbox-content';
    const copy = element.cloneNode(true);
    copy.removeAttribute('style');
    if (copy.tagName.toLowerCase() === 'svg') {
      copy.setAttribute('width', '100%');
      copy.setAttribute('height', '100%');
    }
    frame.appendChild(copy);
    overlay.appendChild(hint);
    overlay.appendChild(frame);

    function close() {
      overlay.remove();
      document.removeEventListener('keydown', onKey);
    }
    function onKey(event) { if (event.key === 'Escape') close(); }
    overlay.addEventListener('click', close);
    document.addEventListener('keydown', onKey);
    document.body.appendChild(overlay);
  }

  // Écoute au niveau du document : le script est chargé avant que la page (#content) existe.
  document.addEventListener('click', function (event) {
    const target = event.target;
    if (!target || !target.closest || !target.closest('#content')) return;
    const diagram = target.closest('pre.mermaid');
    if (diagram && !diagram.classList.contains('mermaid-error') && diagram.querySelector('svg')) {
      openLightbox(diagram.querySelector('svg'));
      return;
    }
    if (target.tagName === 'IMG' && !target.closest('a')) openLightbox(target);
  });

  // resetScroll = true quand on ouvre une autre page ; false pendant la frappe (on garde la position).
  // context = { base: dossier de la page, pages: noms de pages connus (normalisés) }
  window.renderMarkdown = function (source, resetScroll, context) {
    context = context || {};
    lastRender = { source: source, context: context };
    applySettings(context);
    const scrollY = window.scrollY;
    const content = document.getElementById('content');
    content.innerHTML = md.render(source);
    invalidateBlocks();
    renderCallouts(content);
    renderTaskLists(content, context.interactiveTasks === true);
    renderWikiLinks(content, context.pages, context.base);
    renderSecrets(content, context.secretNames);
    renderTags(content);
    resolveImages(content, context.base);
    addCopyButtons(content);
    window.scrollTo(0, resetScroll ? 0 : scrollY);
    if (resetScroll === true) {
      // Changement de page : léger fondu d'apparition.
      content.classList.remove('page-enter');
      void content.offsetWidth;
      content.classList.add('page-enter');
    }
    updateProgress();
    return renderMermaid(content, context.autoVertical !== false, resetScroll === true);
  };

  // Barre de lecture : fine ligne en haut qui montre où on en est dans la page.
  let progressBar = null;
  let progressQueued = false;
  function updateProgress() {
    if (!progressBar) {
      progressBar = document.createElement('div');
      progressBar.id = 'reading-progress';
      document.body.appendChild(progressBar);
    }
    const scrollable = document.documentElement.scrollHeight - window.innerHeight;
    progressBar.style.opacity = scrollable > 40 ? '1' : '0';
    progressBar.style.transform = 'scaleX(' + (scrollable > 0 ? Math.min(window.scrollY / scrollable, 1) : 0) + ')';
  }
  window.addEventListener('scroll', function () {
    if (progressQueued) return;
    progressQueued = true;
    requestAnimationFrame(function () { progressQueued = false; updateProgress(); });
  }, { passive: true });
  window.addEventListener('resize', updateProgress);

  // Défilement synchronisé : affiche en haut le bloc qui correspond à la ligne `line` de l'éditeur.
  let pendingLine = null;

  // Positions des blocs (ligne du texte -> hauteur dans la page), calculées une fois puis gardées :
  // relire la mise en page de tous les blocs à chaque image saccadait le défilement.
  let blockCache = null;
  let blockObserver = null;
  function invalidateBlocks() { blockCache = null; }

  function blockPositions() {
    if (blockCache) return blockCache;
    const content = document.getElementById('content');
    if (!blockObserver && window.ResizeObserver && content) {
      // Image chargée, schéma dessiné, fenêtre redimensionnée : les positions changent.
      blockObserver = new ResizeObserver(invalidateBlocks);
      blockObserver.observe(content);
    }
    blockCache = [];
    let lastLine = -1;
    let lastTop = -1;
    document.querySelectorAll('#content [data-line]').forEach(function (el) {
      const line = Number(el.getAttribute('data-line'));
      const top = el.getBoundingClientRect().top + window.scrollY;
      if (line > lastLine && top >= lastTop) {
        blockCache.push({ line: line, top: top });
        lastLine = line;
        lastTop = top;
      }
    });
    return blockCache;
  }
  window.scrollToLine = function (line) {
    const first = pendingLine === null;
    pendingLine = line;
    if (!first) return;
    window.requestAnimationFrame(function () {
      const target = pendingLine;
      pendingLine = null;
      const blocks = blockPositions();
      if (!blocks.length || target < blocks[0].line) { window.scrollTo(0, 0); return; }
      // Dernier bloc qui commence avant la ligne visée (recherche dichotomique).
      let low = 0;
      let high = blocks.length - 1;
      while (low < high) {
        const middle = (low + high + 1) >> 1;
        if (blocks[middle].line <= target) low = middle; else high = middle - 1;
      }
      const before = blocks[low];
      const after = blocks[low + 1];
      let y = before.top;
      if (after) {
        // Interpolation entre deux blocs : défilement continu, même dans un long tableau ou bloc de code.
        y += (after.top - before.top) * (target - before.line) / (after.line - before.line);
      }
      window.scrollTo(0, Math.max(y - 16, 0));
    });
  };

  // Sommaire : fait défiler jusqu'au n-ième titre (ou au premier titre portant ce texte).
  window.scrollToHeading = function (index, text) {
    const headings = Array.prototype.slice.call(
      document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6')
    );
    let target = headings[index];
    if (!target || normalize(target.textContent) !== normalize(text)) {
      target = headings.find(function (h) { return normalize(h.textContent) === normalize(text); }) || target;
    }
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
})();
