<div align="center">

<img src="../../Dusty/Dusty/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" height="96" alt="">

# Dusty

**Libérez de l'espace disque sur votre Mac, et voyez chaque fichier avant sa suppression.**

Une alternative gratuite et open source à CleanMyMac, qui se loge dans votre barre des menus.

[![Release](https://img.shields.io/github/v/release/yagcioglutoprak/dusty?color=3b82f6&label=Release)](https://github.com/yagcioglutoprak/dusty/releases/latest)
[![CI](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml/badge.svg)](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/github/license/yagcioglutoprak/dusty?color=6366f1)](../../LICENSE)
[![Stars](https://img.shields.io/github/stars/yagcioglutoprak/dusty?label=Stars&color=38bdf8)](https://github.com/yagcioglutoprak/dusty/stargazers)

[English](../../README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · **Français** · [Русский](README.ru.md)

[**Télécharger**](https://github.com/yagcioglutoprak/dusty/releases/latest) ·
[Installation](#installation) ·
[Ce qu'il nettoie](#ce-que-dusty-nettoie) ·
[Pourquoi c'est sûr](#pourquoi-lui-faire-confiance) ·
[Ligne de commande](#ligne-de-commande-et-raccourcis) ·
[FAQ](#faq)

<br>

<img src="../screenshots/demo.gif?v=4" width="480" alt="L'accueil de Dusty au premier lancement, une analyse qui progresse, l'espace récupérable par niveau, un Nettoyage sûr avec son compte à rebours de restauration, puis le niveau Développeur élément par élément">

<sub>Si Dusty vous fait gagner de la place, une étoile sur GitHub aide d'autres utilisateurs de Mac à trouver un nettoyeur plus sûr.</sub>

</div>

> Cette page est une traduction. Le [README en anglais](../../README.md) est toujours le plus à jour.

## En bref

- **Il montre ce qu'il fait.** Chaque chemin et sa taille s'affichent à l'écran
  avant toute suppression. Analyser ne supprime jamais rien.
- **Il ne peut toucher qu'aux fichiers inutiles.** Les suppressions se limitent
  à une liste blanche fixe et lisible de caches et de fichiers résiduels. Vos
  documents, vos photos et vos e-mails sont hors de portée par conception.
- **Chaque nettoyage est réversible.** Les éléments passent par la Corbeille,
  avec un bouton Restaurer pendant quelques secondes, et chaque suppression est
  écrite dans un journal.
- **Il connaît les fichiers inutiles des développeurs.** DerivedData Xcode,
  simulateurs, caches npm, Cargo et pip, et les `node_modules` des projets que
  vous avez oubliés.
- **Il est rapide.** L'analyse complète d'une machine de développement utilisée
  au quotidien (M3, environ 18 Go répartis sur 866 chemins) prend environ 5 secondes.
- **Il sait se faire oublier.** L'espace libre s'affiche dans votre barre des
  menus, une analyse en arrière-plan tient à jour le chiffre « à nettoyer », et
  l'app se met à jour toute seule.
- **Il ne coûte rien.** Gratuit, sous licence MIT, sans compte, sans télémétrie.

## Installation

```bash
brew install --cask yagcioglutoprak/tap/dusty
```

Ou téléchargez `Dusty.dmg` depuis la
[dernière version](https://github.com/yagcioglutoprak/dusty/releases/latest),
glissez-le dans Applications, puis ouvrez-le. Dans les deux cas, l'app est
signée et notarisée par Apple.

Dusty apparaît dans votre barre des menus sous la forme d'une icône de disque,
avec votre espace libre à côté. Il nécessite macOS 13 Ventura ou version
ultérieure et se tient à jour tout seul (vous pouvez désactiver cette option
dans Réglages).

Le panneau parle aussi français. Il suit la langue de votre Mac, ou vous pouvez
la choisir dans **Réglages > Général**.

## Fonctionnement

1. **Analysez.** Cliquez sur l'icône de disque et lancez une analyse. Dusty
   mesure chaque cible de nettoyage et répartit ce qu'il trouve en trois
   niveaux, les plus volumineux en premier.
2. **Vérifiez.** Un clic suffit pour nettoyer le niveau Sûr. Vous pouvez aussi
   ouvrir n'importe quel niveau et décocher, élément par élément, tout ce que
   vous voulez garder. La barre du bas indique toujours ce qu'un nettoyage
   emporterait.
3. **Nettoyez, avec retour possible.** Une confirmation liste chaque chemin,
   ainsi que votre espace libre avant et après. Après le nettoyage, vous avez
   quelques secondes pour changer d'avis : cliquez sur Restaurer (ou ⌘Z) et les
   éléments nettoyés reviennent à leur place.

<p align="center">
<img src="../screenshots/overview.png" alt="Le panneau de Dusty : l'écran d'accueil avec une barre de stockage et le Nettoyage sûr en un clic, le niveau Développeur élément par élément, la fenêtre de confirmation et les Réglages">
</p>

## Ce que Dusty nettoie

Trois niveaux, de « à faire à tout moment » à « regardez bien avant d'agir ».

| Niveau | Ce qu'il supprime | Pourquoi c'est sûr |
| --- | --- | --- |
| 🟢 **Sûr** | Caches utilisateur, journaux des apps, Corbeille, caches des navigateurs (Safari, Chrome, Firefox, Edge, Brave, Arc) et caches d'apps (Slack, Discord, Notion, Spotify, VS Code, Cursor, Signal, Obsidian, Microsoft Teams, installeurs de mise à jour Zoom, cache multimédia Telegram) | Se régénère tout seul, aucun impact sur le fonctionnement |
| 🟣 **Développeur** | DerivedData Xcode, anciens DeviceSupport, simulateurs indisponibles, caches des gestionnaires de paquets (npm, yarn, pnpm, pip, uv, Bun, Deno, Cargo, Go, Homebrew, Composer, Gradle, CocoaPods, SwiftPM, Dart/Flutter pub), cache des binaires Cypress, caches des outils de dev dans `~/.cache`, caches JetBrains et Unity, dépôt local Maven (à activer), `docker system prune` en option | Se recompile ou se retélécharge la prochaine fois que vous en avez besoin |
| 🟠 **Profond** | Anciens installeurs `.dmg` / `.pkg` dans Téléchargements, archives Xcode, simulateurs inutilisés, instantanés locaux Time Machine, anciens journaux de diagnostic, modèles Ollama (à activer), artefacts de projets abandonnés | Rien n'est sélectionné tant que vous ne l'avez pas coché |

**Projets oubliés.** Le niveau Profond regarde aussi dans vos projets. Il repère
les `node_modules`, le dossier `target` de Cargo ou le virtualenv d'un projet
auquel vous n'avez pas touché depuis un mois. Le manifeste de l'outil doit se
trouver juste à côté de l'artefact, l'activité est évaluée d'après vos propres
fichiers et votre historique git, et si vous touchez à un projet entre l'analyse
et le nettoyage, ses artefacts sont exclus.

**Observations.** Après une analyse, Dusty signale ce qu'une personne
remarquerait : 12 Go de DerivedData alors qu'Xcode n'est plus installé, un cache
dans lequel rien n'a écrit depuis le printemps, un disque en passe d'être plein
dans trois semaines. Les observations ne font que signaler : elles ne
sélectionnent et ne suppriment jamais rien.

**Mode mains libres.** Une analyse en arrière-plan (activée par défaut, toutes
les 4 heures) tient à jour le chiffre de la barre des menus et ne supprime
jamais rien. Le nettoyage automatique (désactivé par défaut) s'exécute selon un
calendrier, ou quand l'espace libre passe sous un seuil que vous choisissez, et
suit les mêmes règles que le panneau.

## Pourquoi lui faire confiance

« Nettoyeur pour Mac » veut généralement dire « app qui supprime des choses que
vous ne voyez pas ». Dusty est conçu à l'inverse. La logique de suppression est
un package Swift séparé et entièrement testé (`CleanerEngine`), sans interface,
et un seul composant, `SafetyValidator`, peut autoriser une suppression. Il
applique les règles suivantes :

- **Liste blanche uniquement.** Un chemin n'est supprimable que s'il se trouve
  sous une cible explicite de [`CleanupTargetRegistry`](../../CleanerEngine/Sources/CleanerEngine/CleanupTargetRegistry.swift).
  Aucune logique du type « tout supprimer sauf » n'existe dans le code.
- **Les dossiers protégés sont intouchables.** Documents, Bureau, Images, la
  photothèque Photos, Musique, Films, Mail, iCloud Drive, les trousseaux et
  Application Support sont refusés, même en tant que préfixes (à l'exception des
  sous-dossiers de cache précis désignés par des cibles enregistrées).
- **Aucune échappée par lien symbolique.** Les liens symboliques ne sont jamais
  suivis, y compris lorsqu'un dossier parent en est un.
- **Pas de root.** Dusty ne s'exécute jamais en root et n'utilise jamais `sudo`,
  et rien de ce qui est protégé par SIP n'est touché.
- **Restauration à chaque niveau.** Les nettoyages placent d'abord les éléments
  dans la Corbeille, et les restaurations sont vérifiées de la même façon que
  les suppressions.
- **Simulation.** Un seul réglage suffit pour que chaque nettoyage indique ce
  qu'il supprimerait, sans rien supprimer.
- **Une trace écrite.** Chaque action (heure, chemin, octets) est ajoutée à
  `~/Library/Application Support/Dusty/deletion-log.jsonl`.

La présentation détaillée de la conception, avec le code :
[Comment Dusty est conçu pour ne pas supprimer ce qu'il ne faut pas](https://toprak.sh/dusty/safety/) (en anglais).
Vous avez trouvé un moyen de lui faire supprimer quelque chose hors de la liste
blanche ? Merci de le signaler en privé : consultez [SECURITY.md](../../.github/SECURITY.md).

## Mémoire

Ouvrez **Mémoire** depuis l'accueil (ou la pastille RAM en haut) pour voir ce
qui occupe votre RAM et la récupérer.

- **La vraie image.** La mémoire utilisée, répartie comme dans le Moniteur
  d'activité (apps, système, compressée, fichiers en cache), le swap, la
  dernière heure en un coup d'œil, et la pression mémoire : c'est elle qui dit
  si votre Mac manque vraiment de mémoire.
- **Des apps, pas des processus.** Le total de chaque app compte tous les
  processus qui travaillent pour elle : les assistants de Chrome, les pages de
  Safari, les outils lancés depuis un terminal.
- **Les apps inactives, déjà cochées.** Les grosses apps que vous n'avez pas
  utilisées depuis une heure sont suggérées. Jamais les terminaux, les machines
  virtuelles, les appels, ni ce qui joue ou enregistre du son.
- **Libérer, avec retour possible.** Un geste quitte les apps suggérées après
  une confirmation qui les liste toutes. Elles se ferment comme avec ⌘Q, donc
  celles qui ont du travail non enregistré vous le demandent. Pendant quelques
  secondes, **Rouvrir** (ou ⌘Z) les ramène toutes.
- **Les fuites, repérées.** Une app qui ne cesse de grossir est signalée, avec un
  bouton **Relancer** qui lui rend une mémoire neuve.

Dusty ne force jamais une app à quitter, ne tue aucun processus et ne lance pas
`purge` : il faut être root pour ça, et cela ne vide que le cache de fichiers
que macOS rend déjà à la demande.

## Ligne de commande et Raccourcis

Le même moteur, la même liste blanche et les mêmes règles de sécurité, en
version scriptable. L'outil en ligne de commande `dusty` est intégré à l'app, et
le cask Homebrew l'ajoute à votre `PATH` :

```bash
dusty scan                                    # mesure les trois niveaux, ne supprime rien
dusty scan --json                             # idem, dans un format lisible par machine
dusty clean                                   # affiche le plan de suppression du niveau Sûr
dusty clean --yes                             # effectue réellement la suppression
dusty clean --level developer --trash --yes   # place les caches de dev dans la Corbeille
dusty targets                                 # affiche toute la liste blanche
dusty memory                                  # mémoire utilisée, pression, apps les plus gourmandes (lecture seule)
```

`clean` ne touche à rien sans `--yes`, ne supprime que les éléments que l'app
sélectionnerait d'elle-même, et ignore toute cible dont l'app est ouverte. Deux
actions Raccourcis, **Nettoyer les éléments sûrs** et **Obtenir l'espace
récupérable**, intègrent Dusty à n'importe quelle automatisation macOS.

## FAQ

**C'est vraiment gratuit ?**
Oui. Licence MIT, sans période d'essai, sans offre payante, sans compte.

**Peut-il supprimer mes projets ou mes documents ?**
Non. Ces dossiers sont refusés par le validateur avant que quoi que ce soit ne
soit touché, et seuls les chemins de caches et d'artefacts de la liste blanche
entrent en jeu. Même pour un projet oublié, seuls ses artefacts de build sont
proposés, jamais votre code.

**Et si je nettoie quelque chose dont j'avais besoin ?**
Cliquez sur Restaurer (ou appuyez sur ⌘Z) dans les secondes qui suivent le
nettoyage, et les éléments reviennent à leur place. La seule exception est le
vidage de la Corbeille, qui est définitif, exactement comme dans le Finder.

**Pourquoi pas le Mac App Store ?**
L'App Store impose le sandboxing, et une app en sandbox ne peut pas accéder aux
caches que Dusty nettoie.

D'autres réponses (Accès complet au disque, mises à jour, compilation depuis les
sources) se trouvent dans le [README en anglais](../../README.md).

## Contribuer

Les pull requests sont les bienvenues, en particulier pour de nouvelles cibles
de nettoyage et des traductions. Consultez [CONTRIBUTING.md](../../CONTRIBUTING.md)
et l'[issue consacrée aux traductions](https://github.com/yagcioglutoprak/dusty/issues/33).

## Licence

MIT. Voir [LICENSE](../../LICENSE).

---

<div align="center">
créé par <a href="https://toprak.sh">toprak.sh</a>
</div>
