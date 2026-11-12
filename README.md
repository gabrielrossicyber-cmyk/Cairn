# Cairn

App macOS (puis iOS) de documentation technique, en fichiers Markdown locaux. Étape actuelle : **semaines 4 et 5** (édition).

## Raccourcis

| Raccourci | Action |
|---|---|
| Cmd+Maj+D | Tableau de bord (pages par section, tâches à faire, questions, modifications récentes) |
| Cmd+K | Rechercher dans tout le wiki (mode « Code » : seulement dans les blocs de code) |
| Cmd+, | Réglages (nom du wiki, police, aperçu, modèle par défaut, variables globales, PDF) |
| Cmd+D | Ajouter / retirer la page des favoris |
| Cmd+Maj+O | Afficher le sommaire de la page |
| Cmd+Maj+F | Mode concentration (masque l'arborescence et les barres) |
| Cmd+Maj+M | Carte des liens de la page ouverte |
| Cmd+Maj+X | Mode examen chronométré |
| Cmd+L | Verrouiller la page avec un mot de passe / la reverrouiller |
| Cmd+Maj+I | Importer des documents (md, txt, pdf, docx, rtf, html, images) |
| Cmd+Maj+E / Cmd+P | Exporter la page en PDF (A4) / imprimer |
| Cmd+Option+E | Exporter tout le wiki : un PDF par page, mêmes dossiers, dans un .zip (pages verrouillées exclues) |
| Cmd+N / Cmd+Maj+N | Nouvelle page / nouveau dossier (dans le dossier sélectionné) |
| Cmd+1 / 2 / 3 | Lecture / Édition / Côte à côte |
| Cmd+S | Enregistrer (sinon automatique 1 s après la dernière frappe) |
| Cmd+F | Rechercher dans la page (en mode édition) |
| Cmd+R | Relire le dossier depuis le disque |
| Cmd+O | Changer de dossier racine |
| Clic droit | Renommer, déplacer, monter/descendre, corbeille, afficher dans le Finder |
| Glisser-déposer | Déplacer une page ou un dossier dans un autre dossier |

## Sécurité et performances

- Aperçu (WebKit) : Content-Security-Policy stricte (seuls les scripts de l'app s'exécutent, aucune connexion sauf images https), HTML brut désactivé, Mermaid en mode strict, navigation en liste blanche.
- Fichiers du wiki servis à l'aperçu : uniquement dans le dossier du wiki (« .. » et liens symboliques résolus), 300 Mo max. Un lien vers une app ou un script n'est jamais lancé (montré dans le Finder).
- Import HTML : scripts, cadres et ressources distantes retirés avant conversion (rien ne part sur le réseau).
- Chargement du wiki en arrière-plan ; index incrémental (seules les pages modifiées sont relues) ; coloration de l'éditeur limitée au paragraphe modifié ; aperçu regroupé pendant la frappe et schémas mis en cache.

## Apparence

Réglages (Cmd+,) › Général › Thème : comme le système, clair ou sombre. Les PDF et l'impression restent toujours en clair.

## Couleurs de dossier

Clic droit sur un dossier › Couleur du dossier (12 couleurs, ou aucune). La couleur est enregistrée dans un fichier caché `.color` du dossier : elle le suit quand on le renomme, le déplace ou le duplique, et se synchronise avec iCloud.

## Tags

- Dans l'en-tête : `tags: iso27001, Analyse des besoins` (ou `tags: [iso27001, iam]`, ou une liste `- iam`). Seule la virgule sépare les tags : un tag de l'en-tête peut contenir des espaces.
- Dans le texte : `#iam`, `#ISO27001` (un seul mot, pas dans le code ; « # Titre » avec espace reste un titre).
- Majuscules et accents ignorés : `#Réseau` = `#reseau`.
- Clic sur un tag (page, en-tête, barre latérale › Tags) : recherche filtrée sur ce tag.

## Carte des liens (Cmd+Maj+M)

Une page au centre, un seul niveau, sans physique ni nuage de points :
- à gauche, les pages qui la citent ; à droite, les pages qu'elle cite avec `[[…]]` (pointillé = page à créer) ;
- en bas, les pages qui partagent ses tags.

Clic sur une page : la carte se recentre sur elle. Échap ou « Lire la page » : retour au texte.

## Recherche filtrée (Cmd+K)

- Menus « Dossier » et « Tag » sous le champ de recherche ; le filtre dossier reste actif d'une recherche à l'autre.
- `#tag` directement dans la recherche : `#iam kerberos` (le début du tag suffit : `#ia`).
- Sans texte, la liste montre toutes les pages du filtre.

## Mode examen (Cmd+Maj+X)

- Questions tirées au hasard des blocs `/question` (question sur une ligne, réponse dans l'encadré `> [!REPONSE]` juste en dessous).
- Périmètre : dossier et/ou tag ; nombre de questions ; durée. Le chrono arrête l'examen à zéro.
- Tu écris ta réponse, tu affiches la correction, tu te notes : Faux / Partiel / Juste (Cmd+1/2/3).
- Note sur 6 (barème suisse : 1 + 5 × points / maximum, arrondie au demi-point, réussi dès 4).
- Historique des 50 derniers examens enregistré dans le wiki ; « Refaire les questions ratées ».

## Tableau de bord (Cmd+Maj+D)

« Personnaliser » : ajouter, retirer, déplacer (↑ ↓), passer en pleine ou demi-largeur, régler chaque widget.
Widgets : chiffres clés, compte à rebours (ex. examen), question de révision au hasard (blocs /question),
à faire, modifiées récemment, favoris, contenu d'un dossier, pages par section, note libre.
Les widgets de liste peuvent être limités à un dossier. Disposition enregistrée par wiki (.secuwiki.json).

## Importer des documents

- Menu Fichier › Importer, bouton « + », clic droit sur un dossier, ou glisser des fichiers depuis le Finder sur l'arborescence.
- `.md` / `.txt` : copiés tels quels (en-tête ajouté si absent).
- `.docx` / `.rtf` / `.html` / `.odt` : convertis en Markdown (titres, listes, gras, liens).
- `.pdf` : copié dans `assets/`, affiché dans la page, et son texte extrait dans un bloc repliable « Extrait » → trouvable avec Cmd+K.
- Images : copiées dans `assets/` avec une page qui les affiche.

## Pages verrouillées

- Page › Verrouiller avec un mot de passe (Cmd+L) : le contenu est chiffré sur le disque (AES-256-GCM, clé dérivée par PBKDF2-SHA256, 600 000 itérations). Seuls l'id, le titre et les dates restent en clair.
- Une page déverrouillée le reste jusqu'à Cmd+L, « Verrouiller toutes les pages », la veille, le verrouillage de la session ou la fermeture de l'app. La clé n'existe qu'en mémoire.
- Le contenu d'une page verrouillée n'est pas indexé par la recherche (seul le titre l'est).
- Pas de récupération : mot de passe perdu = page perdue.
- Les images et PDF joints (dossier assets/) ne sont pas chiffrés : seul le texte de la page l'est.
- Verrouiller une page existante n'efface pas ses anciennes copies en clair (Time Machine, versions iCloud). Pour un secret, crée la page et verrouille-la avant d'écrire dedans.

## Schémas simples (/flux)

```flux
Préparer > Détecter > Contenir > Éradiquer
Détecter > Faux positif ? > [oui] Clore
```

- Une ligne = une chaîne d'étapes ; séparateurs `>`, `->`, `→` ou `=>`.
- Même nom sur plusieurs lignes = même case (pour faire des branches).
- `?` à la fin = décision (losange) ; `(Début)` = case arrondie ; `[oui]` = texte sur la flèche.
- Ligne `vertical` = de haut en bas (horizontal par défaut).

## Dans l'éditeur

| Raccourci | Action |
|---|---|
| `/` | Menu des commandes (flèches, Entrée pour insérer, Échap pour fermer) |
| Tab / Maj+Tab dans un tableau | Cellule suivante / précédente ; Tab en fin de tableau ajoute une ligne |
| Entrée dans une liste | Nouvel élément (`-`, `1.`, `- [ ]`) ; Entrée sur un élément vide termine la liste |
| Cmd+B / Cmd+I / Cmd+Maj+C | Gras / italique / code |
| Cmd+Option+T | Insérer un tableau |
| Cmd+Option+C | Insérer une commande bash |

Modèles de page `/` : `/cours`, `/revision`, `/lab`, `/incident`, `/glossaire`, `/cve`, `/mitre`, `/outil`, `/procedure` (modèles dans `Editor/SlashTemplates.swift`).

Productivité :
- **Nouvelle page (Cmd+N)** : titre + choix du modèle. Modèles proposés réglables dans Réglages > Modèles et variables.
- **Mes modèles** : chaque fichier .md du dossier `_Modèles/` devient un modèle et une commande `/`.
- **Renommer** une page met à jour les liens `[[…]]` qui pointent vers elle. **Dupliquer** : clic droit.
- **Cases à cocher** cliquables dans l'aperçu. **Tableaux** alignés automatiquement à chaque Tab.
- **Rafraîchissement automatique** quand un fichier change (iCloud, Finder). **Côte à côte** : l'aperçu suit le défilement de l'éditeur.
- **Variables** : `{{IP_CIBLE}}` dans le texte, valeur dans la barre Variables (enregistrée dans l'en-tête `vars:`).
- **Liens internes** : `[[Nom de page]]` ou `[[Nom|texte]]`, avec suggestions en tapant `[[`. Lien rouge = page à créer. « Mentionnée dans » en bas de page.
- **Images** : Cmd+V d'une capture ou d'un fichier image -> copié dans `assets/` à côté de la page.
- **Révision** : `/question` et `/reponse` -> réponse masquée, cliquer pour l'afficher.
- **Schémas** (Mermaid) : `/schema`, `/sequence`, `/classe`, `/etat`, `/activite`, `/er`, `/bpmn` (tape `/uml` pour voir tous les diagrammes UML).
- **Lien [[…]] cliqué** : la page s'affiche dans un panneau à droite (« Ouvrir » pour y aller, × pour fermer).

Encadrés colorés : `/information` (bleu), `/attention` (rouge), `/avertissement` (orange), `/astuce` (vert).
Syntaxe compatible GitHub : `> [!NOTE]`, `> [!CAUTION]`, `> [!WARNING]`, `> [!TIP]`, `> [!IMPORTANT]`.

Autres commandes `/` : `/table`, `/bash`, `/powershell`, `/python`, `/yaml`, `/code`, `/h1` `/h2` `/h3`, `/todo`, `/liste`, `/etapes`, `/note`, `/attention`, `/lien`, `/image`, `/separateur`, `/date`.
Elles sont définies dans `Editor/SlashCommand.swift` : pour en ajouter une, copie un bloc existant.

## Lancer l'app

1. Ouvre `SecuWiki.xcodeproj` dans Xcode.
2. Clique sur le projet **SecuWiki** (en haut à gauche) › cible **SecuWiki** › onglet **Signing & Capabilities**.
3. Dans **Team**, choisis ton « Personal Team » (ton identifiant Apple). Si tu n'en as pas : *Add an Account…*.
4. Appuie sur **Cmd+R**.
5. Au premier lancement, choisis le dossier `Wiki-Exemple` pour tester.

## Structure du code

| Dossier | Rôle |
|---|---|
| `App/` | Point d'entrée, menus et raccourcis |
| `Store/` | État central (dossier, arborescence, sélection) |
| `Models/` | `WikiNode` : un dossier ou une page |
| `Services/` | Lecture du dossier, de l'en-tête YAML, accès sandbox |
| `Views/` | Interface SwiftUI |
| `Preview/` | Rendu HTML : markdown-it, highlight.js (en local) |

Tout fichier ajouté dans `SecuWiki/` apparaît automatiquement dans Xcode.

## Règles du wiki

- Un dossier = une section. Son `index.md` (facultatif) est sa page.
- Un fichier `.md` = une page. Les `-` du nom s'affichent comme des espaces.
- Un fichier `.order` (une ligne par nom, sans `.md`) impose l'ordre ; sinon tri par nom (`01-`, `02-`…).
- Les dossiers `assets/` sont ignorés dans l'arborescence.
