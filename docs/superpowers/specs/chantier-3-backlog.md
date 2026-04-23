# Chantier 3 — Backlog

**Statut** : en standby, à planifier.
**Contexte** : les chantiers 1 ([vue Organisation de l'agenda](2026-04-23-agenda-organisation-view-design.md)) et 2 ([ODJ + décisions](2026-04-23-organisation-agenda-items-decisions-design.md)) ont outillé la création des moments collectifs et la mémoire des décisions. Restent les fonctionnalités du rôle « Gardien des plannings et ODJ » qui touchent à la vie des sourciers autour d'un gathering.

## Pistes identifiées (non priorisées)

### A. Rappels automatiques
Le doc du rôle Gardien mentionne explicitement : « Il émet un **rappel** aux sourciers lorsque il sent que c'est utile de le faire » — préparation, présence, souper collectif, etc.

- Mails et/ou notifs Claudy (banner in-app) envoyés avant un gathering.
- Règles configurables par catégorie : ex. "PUD → rappel 48h avant avec ODJ en pièce jointe, rappel 2h avant pour le souper".
- Scheduler : Solid Queue / GoodJob / sidekiq-cron — à trancher selon ce qui tourne déjà en prod.
- Templates Postmark (déjà utilisé dans l'app).
- Besoin préalable : connaître les emails de tous les sourciers (`Human#email` existe déjà).
- **Dépendance** : présences (B) si on veut rappeler "t'as pas encore RSVP".

### B. Présences / RSVP
Mentionné comme non-goal du chantier 1. Laissé en standby.

- Nouveau modèle `Attendance` (ou `GatheringAttendance`) : `gathering_id`, `human_id`, `status` (present/absent/maybe), `note`.
- UI : sur la page gathering, liste des humains actifs du cycle avec boutons RSVP + vue synthétique "X présents · Y peut-être · Z absents".
- Peut-être combiné avec le souper collectif : "je reste manger oui/non".
- Visible par tous.

### C. Rôle « Gardien » explicite
Transformer le rôle théorique du doc en entité Claudy.

- Assigner un (ou plusieurs) Human comme gardien, potentiellement par cycle (`Cycle#gardien_human_id` ou table `CycleRole`).
- Dashboard dédié `/organisation/gardien` : "tes gathering sans ODJ · tes gathering à J-3 · décisions non consignées depuis le dernier PUD".
- Badge « Gardien du cycle » sur la fiche humain.
- Préfigure d'autres rôles (pôle urba, accueil, etc.) — poser les fondations en pensant à ça.

### D. Export PV / PDF
Générer un PV à partir d'un gathering : métadonnées + ODJ (points traités/non traités) + décisions prises.

- Gem possible : `wicked_pdf` ou `prawn` (tout dépend de ce qui tourne déjà).
- Template HTML imprimable → PDF.
- Action `GET /gatherings/:id.pdf` qui streame le fichier.
- Utile après un PUD pour archiver/partager avec des sourciers absents.

### E. Suivi des décisions dans le temps
Prolonge le registre existant.

- Notifications quand une décision ancienne est "citée" dans un nouveau PUD (via les décisions).
- Timeline des décisions par thème (nécessite tags — reporté au chantier 2 mais revient ici si besoin).

### F. Quality of life divers
Petits sujets accumulés pendant les chantiers 1-2, à traiter au fil.

- Récurrence simple sur gatherings (ex. "PUD tous les 15 jours jusqu'au…") — pour réduire le 2-clics × N.
- Drag & drop accessibility fallback (boutons ↑/↓ pour clavier).
- Filtres sur `/organisation/decisions` (année, catégorie de gathering).
- Tags sur décisions (si la recherche ILIKE montre ses limites).
- Statut de décision (révisée / annulée) — si besoin émerge.
- Pastille "ODJ vide à J-3" sur la vue Organisation du calendrier (visual cue pour le gardien).

## Dépendances et ordre suggéré

1. **C (Rôle Gardien explicite)** en premier : définit qui reçoit les rappels et à qui s'adresse le dashboard. Petite feature de plomberie qui débloque le reste.
2. **B (Présences)** : modèle de données stable, UI simple, utile tel quel.
3. **A (Rappels)** : s'appuie sur B (présences) et C (gardien qui décide/déclenche).
4. **D (Export PV)** : orthogonal, peut se faire à tout moment si un besoin précis se présente.
5. **E, F** : à piocher selon demande utilisateur.

## À clarifier avant de démarrer

- Est-ce que le chantier 3 choisit **une** piste ou **un combo** (C + B, par exemple) ?
- Les rappels : mail uniquement ou aussi notifs in-app (Turbo Streams broadcasts) ?
- Les présences : un sourcier RSVP pour lui seul, ou peut-il RSVP au nom d'un autre (ex. "Bené a confirmé par message") ?
- Le Gardien : un seul par cycle ou plusieurs co-gardiens ?
- Export PV : format libre ou template standard imposé par le collectif ?
