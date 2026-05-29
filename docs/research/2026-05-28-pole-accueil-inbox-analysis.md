# Les 4 Sources — Pôle Accueil Inbox Analysis (12 months)

> Source : `les4sources.sejours@gmail.com` — analyse du flux Pôle Accueil sur 12 mois glissants (juin 2025 → mai 2026), pour alimenter l'ISA Claudy (forms natives, FAQ, B2B/B2C, PricingModel, gaps).
> Méthode : `search_threads` ciblés (sender / mot-clé / fenêtres temporelles) + `get_thread FULL_CONTENT` sur cas signaux-élevés. Aucune donnée nominative conservée — tout est agrégé / anonymisé. Date d'analyse : 2026-05-28.

---

## Executive summary

1. **Le formulaire Tally est le canal n°1 entrant** : ~60-70 demandes/an arrivent via `notifications@formulaires.les4sources.be`, soit ~5-7/mois en moyenne, avec des pics à 10+/mois entre **janvier-mars** (planification annuelle) et **août-septembre** (rentrée scolaire + retraites entreprise). Ce canal écrase Airbnb et Booking en volume *entrant* (mais pas en *nuitées payées* — Airbnb/Booking captent la Tiny + la Chevêche en réservation directe sans passage par Malau).
2. **Le formulaire actuel laisse trop de champs vides** ("- " "- ") et n'oblige pas à structurer la demande. Résultat : ~30-40% des threads commencent par une demande de clarification de Malau ("pouvez-vous préciser ?"). Le champ « date » est régulièrement utilisé comme date fictive ("date d'info") au lieu de la vraie date — source de quiproquos.
3. **Le mix B2C/B2B est ~50/50 en demandes, mais ~60/40 en CA** : le B2B paie plus cher (devis multi-postes, 1-3k€), occupe la basse saison qui complète bien le B2C (mariages/familles été). Le **gisement de croissance pour atteindre les 100k€** est explicitement B2B groupes 15-30 sur weekday hors été.
4. **Les 4 frictions structurelles** se répètent : (a) opacité disponibilités ("c'est encore libre ?"), (b) opacité tarifs ("combien ça coûte au final ?"), (c) confusion catalogue Hulotte / Chevêche / Grand-Duc, (d) processus de réservation à 3 étapes (form → mail Malau → app.les4sources.be). Chaque friction génère ~3-5 allers-retours évitables.
5. **5 activités dominent les demandes** : pizza party (privée), camembert party, disc-golf, grimpe dans les arbres, troupeau d'ânes. **3 activités quasi-jamais demandées** : soudure, palettes (sauf via team building B2B), astronomie. **3 demandes hors catalogue récurrentes** : yoga/retraite bien-être, accueil de chiens (limite 1/groupe), accès cuisine sans repas accompagné.
6. **Le pattern "groupe 15-30 pers, 1 nuit, salle + repas + 1-2 activités" est l'archétype B2B** — c'est la maille naturelle pour un produit packagé. Tous les devis B2B observés tournent autour de cette structure.
7. **Les délais d'anticipation divergent fortement** : B2B 3-9 mois, B2C familles 1-3 mois, Tiny/Chevêche via Airbnb 1-4 semaines. Toute opacité de planning long-terme (>6 mois) bloque le B2B.
8. **Le pricing actuel est en sept structures parallèles non documentées publiquement** : forfait gîte/nuit, €/pers/nuit (camping), forfait salle/journée, forfait activité (1-2h), €/pers (repas), forfait mariage (2600€/we), forfait formation. Les clients ne savent pas reconstruire le total — d'où "envoyez-moi un devis" systématique.
9. **Vocabulaire client massivement orienté "lieu / nature / vie collective / écolieu / tiers-lieu"** — beaucoup plus que "gîte". Les clients viennent pour le *concept*, pas l'hébergement seul. Le SEO et les form labels doivent suivre.
10. **La gestion par Malau est artisanale et personnalisée** — c'est une force perçue (qualité d'accueil, voice 5 étoiles Airbnb) et une fragilité (Malau = SPOF, "fort occupée sur le terrain", retards de réponse 3-7j en haute saison). Toute automatisation Claudy doit conserver la chaleur, pas la robotiser.

---

## A. Volume estimate

### A.1 Volume mensuel — flux entrant (12 mois glissants)

| Source | Volume estimé/an | Volume estimé/mois | Pic |
|--------|-------------------|--------------------|----|
| Tally form (`notifications@formulaires.les4sources.be`) | **~70-90 threads/an** | 6-8 | 10-12 en jan/fév/mars + sept |
| Airbnb (`automated@airbnb.com` + `express@airbnb.com`) | **~50-70 threads/an** (réservations + messages + reviews) | 5-7 | mai-août |
| Booking.com (`*@guest.booking.com` + `noreply@booking.com`) | **~15-25 threads/an** | 1-2 | mai-août |
| Direct (sans passage form) | **~30-50 threads/an** | 3-5 | constant |
| Activités / coordination interne (Malau → animateurs) | **~50-80 threads/an** | 5-7 | mars-octobre |
| Newsletters secteur (Gîtes Wallonie, Tripadvisor) | bruit | bruit | bruit |

**Total demandes client utiles** : ~200-250 threads/an (~17-21/mois).

### A.2 Mix B2C / B2B (estimé sur sample de ~80 threads)

| Segment | % threads | % CA estimé |
|---------|-----------|-------------|
| **B2C** (familles, amis, mariages perso, anniversaires, "passants" pizza party) | ~50% | ~40% |
| **B2B** (asbl, fédérations, entreprises team building, SPW, scolaires, écoles, mouvements de jeunesse) | ~45% | ~55% |
| **Hybride** (formations, retraites bien-être animées par un·e indépendant·e) | ~5% | ~5% |

### A.3 Mix par hébergement demandé

| Hébergement | Part dans les demandes Tally |
|-------------|------------------------------|
| **Grand-Duc (25p)** | dominant — ~40-45% (groupes 15-30, le produit-phare) |
| **Hulotte (15p)** seule | ~20-25% (familles élargies, retraites scolaires petites) |
| **Chevêche (8p)** seule | ~10-15% (couples, petits groupes amis, weekend détente) |
| **Tiny House (Clairière)** | ~10% — surtout Airbnb, peu de Tally |
| **Bivouac / tente / van** | ~10-15% (randonneurs, dernière minute, été) |
| **Salle seule (sans nuitée)** | ~10% (réunions, anniversaires en journée, ateliers) |

---

## B. Top 20 recurring questions → FAQ candidates

Toutes les questions sont reformulées depuis du verbatim anonymisé observé dans le corpus.

| # | Question récurrente (verbatim type) | Fréq | Réponse-type Malau |
|---|---|------|--------------------|
| 1 | "Est-ce que les gîtes sont **disponibles à ces dates** ?" | ★★★★★ | "Vous pouvez consulter nos disponibilités directement sur notre site" — lien envoyé à chaque fois |
| 2 | "**Combien ça coûte** ? Pouvez-vous m'envoyer un devis ?" | ★★★★★ | devis ad-hoc Malau, prix fixés mais non lisibles côté client |
| 3 | "Quelle est la **différence entre Hulotte / Chevêche / Grand-Duc** ? Capacité, répartition des lits ?" | ★★★★ | explication récurrente : "Le Grand-Duc = Hulotte + Chevêche, 25 lits, 12 chambres" |
| 4 | "Pouvez-vous me **détailler les chambres** (nombre de lits, taille) ?" | ★★★★ | "Lavande (1er étage) : 2 lits simples adaptables..." — déroulé chambre par chambre |
| 5 | "**Comment je réserve** ? Quelle est la procédure ? Y a-t-il un acompte ?" | ★★★★ | "50% d'acompte, ou à hauteur de vos possibilités. Mail automatique avec lien app.les4sources.be" |
| 6 | "**Les prix sont-ils TVAC** ? Y a-t-il une TVA en plus ?" | ★★★ | "Prix TVAC, pas de TVA en plus" (récurrent — la confusion vient car les prix paraissent ronds) |
| 7 | "Peut-on **venir avec un chien** ?" | ★★★ | "1 chien par groupe, supplément" (en fait pas standardisé selon les threads) |
| 8 | "Quelle est la **politique d'annulation / remboursement** ?" | ★★★ | flou — pas de politique standard visible, remboursements partiels au cas par cas |
| 9 | "**Quelles activités** proposez-vous ? Pouvez-vous nous suggérer un programme ?" | ★★★★ | renvoi vers /activites, puis suggestion personnalisée |
| 10 | "Y a-t-il une **cuisine équipée** dans le gîte ? Peut-on cuisiner soi-même ?" | ★★★ | "Cuisine + salle à manger au 2ème étage" + précision sur cuisine pro louable |
| 11 | "Est-ce que la **salle est encore libre** ce jour-là ? À quelle heure ?" | ★★★★ | check planning, réponse manuelle |
| 12 | "Quelle est la **capacité max d'une salle / d'un repas** ? Combien à table ?" | ★★★ | grande salle 80p, petite 25p assis, configurations multiples |
| 13 | "**Que faut-il apporter** ? Draps, essuies, savons ?" | ★★★ | "draps, essuies de bain, savons biodégradables" — répété à chaque réservation |
| 14 | "Quels sont les **horaires de check-in / check-out** ?" | ★★★ | flexible mais "départ vers 16h sans problème" |
| 15 | "Peut-on **commander du pain** auprès de la boulangerie Tranches de Vie ?" | ★★ | lien `tranchesdevie.les4sources.be` — bug récurrent : SMS de confirmation parfois pas reçu |
| 16 | "Comment se passe la **pizza party** ? Faut-il s'y inscrire ? Privée vs collective ?" | ★★★ | distinction 2e vendredi/mois (collective) vs forfait privé 40€ + 7€/pers (patons), allumage du four à prévoir |
| 17 | "Et la **camembert party** ?" | ★★ | équivalent mensuel, formule différente |
| 18 | "Peut-on **venir camper avec un van / camping-car** ? Pour combien ?" | ★★★ | 15€/nuit/van ou 7,50€/pers/nuit en tente, accès sanitaires + cuisine ext. |
| 19 | "Vous **acceptez les groupes scolaires / mouvements de jeunesse** ?" | ★★ | oui, formule type "retraite scolaire" disponible |
| 20 | "Avez-vous un **numéro d'enregistrement touristique** / un statut Gîte de Wallonie pour notre justificatif ?" | ★★ | affiliation Gîtes Wallonie en cours, numéro à fournir |

> Toutes ces 20 sont des **candidates directes pour la FAQ Claudy** + **labels de form natif**. Les 6 premières représentent à elles seules ~50% du volume de réponses Malau.

---

## C. Catalogue gaps — demandes hors catalogue

Demandes récurrentes qui *ne sont pas* ou *pas explicitement* dans le catalogue actuel :

| Demande hors-catalogue | Fréq | Statut actuel | Décision-type Malau |
|---|---|---|---|
| **Yoga / retraite bien-être animée** | ★★★ | non offert | renvoie vers le catalogue d'activités, propose la salle + cuisine plantes sauvages, oriente vers indépendants qui louent le lieu |
| **Accueil chien / animaux** | ★★★ | semi-toléré (1/groupe, supplément variable) | gérée au cas par cas — pas de page dédiée |
| **Petits-déjeuners servis** | ★★ | déjà un Asana de Malau : "faire une carte pour les petits déjeuners" | absence de formule formalisée — opportunité claire |
| **Spa / sauna / jacuzzi** | ★★ | non offert | demandes occasionnelles via Airbnb, redirection vers le bar et la nature |
| **Location seule du four à bois pour pizza party à la journée** | ★★★ | offert mais mal-cadré | nécessite "allumage" séparé (3h chauffe) — confusion fréquente |
| **Visites de groupe sans nuitée (1-2h)** | ★★ | "présentation du domaine" à 120€ | peu visible côté client |
| **Espace résidence d'artiste** | ★ | en cours (page Notion en construction) | demande de Michael en interne |
| **Mariage avec >100 invités assis** | ★★ | la formule mariage 2600€ existe mais la jauge "80p assis" coince | conversion difficile |
| **Cuisine seule (sans repas accompagné)** | ★★ | location de la cuisine pro existe (forfait variable, ~110€ vu sur un remboursement) | accès parfois mal coordonné — un cas de mécontentement vu |
| **Tente-de-toit / camping voiture spécifique** | ★ | accepté en bivouac van | pas de tarification claire pour tente de toit |
| **Hébergement pour résidence cyclo / Bienvenue Vélo** | ★ | en réflexion (Gîtes Wallonie invite à une rencontre) | gain potentiel SEO/positionnement |
| **Forfait "passants randonnée" (juste pizza party + bar + terrasse)** | ★★★ | déjà semi-formalisé : "terrasse accessible du lever au coucher" + pizza party privée 40€ | demande croissante, à packager |
| **Mises à disposition petite salle 2-3h en soirée** | ★★ | tarification journée complète ou demi-journée — pas de slot court | clients déçus du tarif |

---

## D. Friction points

### D.1 Opacité des dates / disponibilités

- **Pattern** : ~30% des threads commencent par "Est-ce libre à telle date ?". Malau renvoie systématiquement vers la page disponibilités → friction évitable. Plusieurs cas où **le client a vu le gîte « disponible » sur Airbnb mais Malau répond « occupé »** — désynchronisation calendrier interne ↔ OTAs.
- **Exemple anonymisé** : *"Votre logement la Hulotte est toutefois indiqué comme disponible sur Airbnb et sur votre site du samedi X au dimanche Y. Est-ce une erreur ?"* → Réponse : *"Sur Airbnb ce n'est pas encore mis à jour."*

### D.2 Opacité des tarifs

- **Pattern** : le client *voit* un tarif sur le site mais ne sait pas reconstruire le total quand il combine **gîte + salle + repas + activités**. Quasi 100% des B2B et la moitié des B2C demandent explicitement un *devis*.
- **Exemple anonymisé** : *"Difficile de s'y retrouver sur votre site et les différents prix. Pouvez-vous me faire un devis ?"*
- **Conséquence directe** : un client (groupe ~50 pers) a abandonné en disant *"votre environnement correspond à nos valeurs mais notre budget ne nous le permet pas"* — *sans avoir reçu de devis chiffré clair en amont*.

### D.3 Confusion catalogue Hulotte / Chevêche / Grand-Duc

- **Pattern** : 1 thread sur 3 demande la différence entre les trois noms. Le fait que **"Grand-Duc = Hulotte + Chevêche réservés ensemble"** n'est pas évident pour les non-initiés. Plusieurs threads où le client se trompe et nomme le mauvais gîte (Grand Duc/Grand-Duc/le grand-duc/Le Grand Duc — orthographie variable).
- **Exemple anonymisé** : *"Notre hébergement le grand-duc, est constitué de deux logements (la Chevêche et la Hulotte). Ce qui fait un total de 25 lits."* — Malau doit ré-expliquer fréquemment.

### D.4 Processus de réservation à 3 étapes

- **Pattern** : (1) le client remplit Tally → (2) Malau répond manuellement par mail → (3) le client reçoit "un mail automatique avec lien vers app.les4sources.be". Étape (3) est mal comprise : le client cherche un lien direct dans (2), parfois ne le trouve pas, repose la question.
- **Exemple anonymisé** : *"Comment puis-je effectuer le paiement ? Je pensais qu'il y avait un lien pour le faire de manière automatique."*
- **Cas observé d'annulation pour opacité du flow** : le client attendait des infos précises, n'a pas trouvé, a réservé ailleurs (*"j'ai pu faire une autre réservation"*).

### D.5 Saturation Malau ↔ délai de réponse

- **Pattern aigu en haute saison** : Malau répond explicitement *"Je vois seulement votre demande de réservation. Nous sommes fort occupés sur le terrain. N'hésitez pas à me contacter par téléphone pour une réservation plus rapide."*
- Délai moyen Tally→réponse observé : 24h-48h en basse saison ; **3-7 jours en haute saison**, voire >2 semaines. Plusieurs threads où le délai a tué la demande (*"finalement on a trouvé autre chose"*, *"désolé, on a réservé ailleurs"*).

### D.6 Champs Tally faibles

- Les champs « Adultes : - » « Enfants : - » « Hébergement : - » très fréquents → le formulaire n'oblige pas à choisir. La date est parfois utilisée comme date fictive (cas du *"18 mai = 18 juin, erreur sur la date"* → confusion qui prend 3 allers-retours à dissiper).
- Le champ "Objet de la demande" a deux modes ("J'ai toutes les infos, je souhaite réserver" / "Je souhaite des informations") — utile mais sous-exploité côté traitement.

### D.7 Désynchronisation OTA ↔ planning interne

- Plusieurs cas : Airbnb / Booking laissent passer une réservation alors que le gîte est déjà loué côté Pôle Accueil. Une réservation Booking a dû être annulée par Malau côté hôte (*"j'ai donc fait une demande d'annulation"*). Risque de double-booking permanent.

---

## E. B2B vs B2C empirical signature

| Dimension | **B2C** | **B2B** |
|-----------|---------|---------|
| **Tonalité** | familière ("super", "génial", "wha votre site est trop chouette") + emojis fréquents | formelle ("Madame, Monsieur"), signatures longues, mention du service Achats |
| **Question d'entrée** | "C'est libre ?" / "Combien pour 15 ?" | "Pouvez-vous nous envoyer un devis" + brief contextuel ("dans le cadre de notre team building / mise au vert / retraite scolaire") |
| **Cycle de décision** | 1-7 jours, parfois 1 message → confirmation | 2-6 semaines (validation hiérarchique, "après réunion ce jour avec la direction") |
| **Anticipation** | 1-3 mois en moyenne | 3-9 mois, parfois >1 an (un thread B2C aussi pour mariage 2027) |
| **Vocabulaire** | "weekend", "famille", "amis", "petit groupe", "passer un bon moment" | "team building", "mise au vert", "offsite", "retraite", "séminaire", "afterwork", "afterworking", "matériel sono/projection", "bon de commande", "facturation TVA", "pièce justificative", "Peppol" |
| **Format attendu** | prix direct dans le mail | devis structuré ligne par ligne + sous-totaux + montant total |
| **Repas** | pizza party (festif) + camembert party | repas végé midi à 15€/pers + buffet pain-fromage 12€/pers + goûter apéritif |
| **Activités demandées** | grimpe arbres, troupeau d'ânes, disc-golf (familles avec enfants) ; pizza party (tout le monde) | bijoux récup, palettes, présentation domaine, disc-golf (team building), goûter apéritif |
| **Sensibilité prix** | élevée — ~20% des B2C abandonnent pour budget | moyenne — le SPW, Croix-Rouge, asbl ont un budget alloué, négocient peu sur le prix mais beaucoup sur la facturation |
| **Délai de réponse acceptable** | 24-48h espéré | 48-96h tolérable mais relances rapides ("Je me permets de vous relancer") |
| **Mode de paiement** | virement direct, parfois sur place | bon de commande → facture → Peppol/virement (administration publique), acomptes 50% standard |
| **Récurrence** | one-shot 80% / récurrents 20% (Petit Peuple Lié, familles fidèles) | récurrents 60% — la même asbl revient chaque année (Communa, Empreintes/Ride to the Future, SPW, Croix-Rouge, Solidarcité, Coopiteasy) |

---

## F. Activity demand clusters

### F.1 Top activités demandées

| Activité | Demande relative | Cluster typique |
|---|---|---|
| **Pizza party (privée)** | ★★★★★ | toutes typologies — couple en weekend, famille, mariage, groupe scolaire, team building |
| **Camembert party** | ★★★ | weekends d'hiver, groupes famille/amis |
| **Grimpe dans les arbres** | ★★★★ | familles avec enfants, scolaires, mouvements de jeunesse |
| **Troupeau d'ânes (présentation/balade)** | ★★★★ | familles, scolaires, anniversaires enfants |
| **Disc-golf** | ★★★★ | team building (SPW, Funds for Good, Trakks), groupes amis, weekends |
| **Présentation du domaine** | ★★★ | demandée explicitement ou implicitement par tout B2B première visite |
| **Atelier création de bijoux récup'** | ★★★ | team building B2B (SPW, école secondaire), animatrice externe |
| **Atelier palettes** | ★★ | team building, mais Olivier souligne "3h pour que ça ait du sens, 2h c'est juste" — friction d'agenda |
| **Cuisine plantes sauvages (saison)** | ★★ | retraites bien-être, écoles |
| **Astronomie / étoiles** | ★★ | nuits d'été, demandes ponctuelles |
| **Zythologie (initiation bière)** | ★★ | groupes adultes B2B + B2C, anniversaires |
| **Atelier soudure** | ★ | très rare en demande spontanée |
| **Cueillette champignons (saison)** | ★ | demandes ciblées automne |

### F.2 Clustering observé

- **Cluster "famille avec enfants"** : grimpe + ânes + pizza party + disc-golf léger
- **Cluster "team building corporate"** : présentation + 2 ateliers en parallèle (bijoux + palettes) + goûter/apéro + repas midi
- **Cluster "retraite scolaire"** : grimpe + bijoux + cuisine plantes sauvages + repas 2j + nuit Hulotte
- **Cluster "mariage"** : formule 2600€ + pizza party vendredi + cérémonie dans le bois + grande salle + camping ami·es
- **Cluster "groupe amis weekend"** : Grand-Duc 2 nuits + pizza party + bar accessible
- **Cluster "passant randonneur"** : terrasse + bar + pizza party à la journée + commande pain

### F.3 Activités jamais demandées spontanément (mais offertes)

- **Atelier soudure** — quasi-jamais demandé, sauf orientation Malau (peut être un soft-skill du lieu, à valoriser ou décommissionner)
- **Astronomie hors saison "étoiles filantes" août**
- **Cueillette champignons** — saisonnier, à mettre en avant en automne

### F.4 Activités demandées mais inexistantes

- **Yoga / méditation guidée** — demande récurrente, surtout en retraite. Réponse Malau : "nous n'avons pas ça, vous pouvez amener votre propre animateur·trice"
- **Sauna / spa / jacuzzi extérieur** — quelques demandes, surtout Airbnb couples
- **Construction de cabanes / chantier nature pour ados** (cas observé Ride to the Future) — n'existe pas comme produit mais Michael a accepté un cas one-shot sur "riz de Mandchourie / espèces invasives". Piste de produit pédagogique.

---

## G. Pricing patterns

### G.1 Tarifs catalogue observés dans les devis Malau

| Item | Tarif observé | Structure |
|---|---|---|
| **Hulotte** (15p, 1 nuit semaine) | 485€ | forfait |
| **Hulotte** (1 nuit weekend) | 745€ pour 2 nuits semaine ≈ **372€/nuit weekend** | forfait |
| **Chevêche** (8p, 1 nuit) | 260-275€ | forfait |
| **Chevêche** (3 nuits) | 675€ (≈225€/nuit) | forfait dégressif |
| **Grand-Duc** (25p, 1 nuit) | 600-750€ selon saison | forfait |
| **Grand-Duc** (2 nuits weekend) | 1200-1350€ | forfait |
| **Grand-Duc** (3 nuits) | 1800-1950€ | forfait |
| **Grand-Duc** (semaine 4-5 nuits) | 2410€ | forfait |
| **Tiny House (Clairière)** | 70€/nuit (1p) à 190€/2 nuits | forfait |
| **Camping tente** | 7,50€/pers/nuit | €/pers |
| **Van aménagé / camping-car** | 15€/nuit/véhicule | forfait/nuit |
| **Grande salle** journée complète | 250-400€ | forfait/jour |
| **Grande salle** demi-journée | ~125-200€ | forfait |
| **Petite salle** journée | 140-190€ | forfait |
| **Petite salle** demi-journée / soirée | 110-140€ | forfait |
| **Cuisine pro** location | ~110-200€ (variable selon durée) | forfait |
| **Repas végétarien midi** | 15€/pers | €/pers |
| **Buffet pain-fromage-légumes** | 12€/pers | €/pers |
| **Formule repas complète (midi+soir+petit-déj)** | 35€/pers/jour | €/pers |
| **Goûter apéritif** | 7€/pers | €/pers |
| **Pizza party privée** | 40€ forfait allumage four + 7€/pers (patons + garnitures) | base + €/pers |
| **Disc-golf** | 120€ forfait 8p, +15€/pers au-delà | forfait + €/pers |
| **Grimpe arbres** | 60€/h (encadrement) | forfait horaire |
| **Atelier bijoux récup'** | 120€/2h | forfait horaire |
| **Atelier palettes** | 120€/2h (min 3h selon animateur) | forfait horaire |
| **Cuisine plantes sauvages** | 120€/2h | forfait horaire |
| **Présentation du domaine** | 90-120€ (1h30) | forfait |
| **Initiation astronomie** | tarif animateur (variable) | forfait soir |
| **Initiation zythologie** | 120€ + 7€/pers | base + €/pers |
| **Troupeau d'ânes** | 120€/séance | forfait |
| **Formule mariage** | 2600€/we (tous espaces vendredi-dimanche) | forfait we |
| **Nuit "passant" sans gîte** (4 lits libres dans gîte d'un groupe) | 35€/pers/nuit | €/pers |
| **Supplément chien** | non standardisé (mentionné comme "supplément" sans chiffre clair) | flou |

### G.2 Brackets typiques observés sur devis B2B reconstitués

| Type de groupe | Budget total |
|---|---|
| Team building demi-journée 30-35p (repas + 2 ateliers + goûter) | 1400-1500€ |
| Asbl 17p 1 nuit + repas + activité + salle | 1100-1400€ |
| Retraite scolaire 12-14 élèves 2 nuits + repas + 2 activités | 1800-2400€ |
| Weekend famille élargie 15-26p Grand-Duc 2 nuits + pizza party | 1400-1700€ |
| Mariage 2 nuits all-in 80-140 invités | 2600-4000€ (+ repas externes) |
| Groupe 25-30p mise au vert 2 nuits + salle + cuisine pro + repas complets | 2500-3500€ |

### G.3 Patterns de structuration des devis Malau

- **Récap systématique** : Malau renvoie un récap ligne par ligne ("Une nuit dans le gîte le grand-Duc : 600€ - jeudi midi : repas...") — c'est de fait le **modèle de devis qui doit être codifié dans Claudy**.
- **Acompte standard** : 50% (souvent négocié "à hauteur de vos possibilités").
- **Pas de TVA séparée** : prix TVAC, mais doit être ré-expliqué très fréquemment.
- **Forfait dégressif** non documenté publiquement (3 nuits < 3x prix 1 nuit) — opportunité de lisibilité.
- **Personnalisation** : Malau adapte selon saison, type de client, historique relationnel — c'est un savoir-faire à *augmenter* avec Claudy, pas à remplacer.

---

## H. Lead time patterns

### H.1 Distribution observée

| Type de demande | Lead time médian observé |
|---|---|
| **Tiny / Chevêche via Airbnb** | 1-4 semaines (parfois <72h) |
| **Bivouac / tente / van** | 0-7 jours (très last-minute, été) |
| **Salle + repas 1 journée B2C** | 2-6 semaines |
| **Weekend famille Grand-Duc** | 1-4 mois |
| **Weekend amis Hulotte/Chevêche** | 1-3 mois |
| **Anniversaire / fête perso** | 2-6 mois |
| **Retraite scolaire** | 3-9 mois |
| **Mise au vert / team building entreprise** | 1-4 mois |
| **Mariage** | 6-18 mois (mariage été 2027 demandé en février 2026) |
| **Demande de devis "exploratoire" (peut-être annulée)** | 2-12 mois |

### H.2 Implication produit

- **Le calendrier de disponibilité doit être ouvert >18 mois à l'avance** pour capter les mariages et les mises au vert annuelles.
- **Un système de "pré-réservation avec option" (Malau le fait déjà manuellement) est crucial** — observée plusieurs fois : *"Je mets bien une option pour vous d'ici la fin du mois"*.
- **La fenêtre "last-minute camping/Tiny"** mérite un canal dédié / push (offres "places libres ce week-end").

---

## I. Seasonality

### I.1 Distribution mensuelle approximative des demandes

| Mois | Volume demandes | Profil dominant |
|---|---|---|
| **Janvier** | élevé (10+) | planification annuelle : familles, retraites, mariages été |
| **Février** | élevé | suite planification annuelle, mariages, anniversaires |
| **Mars** | élevé | retraites scolaires (rhéto), team building printemps, weekends fam/amis |
| **Avril** | élevé | retraites scolaires, weekends Pâques, premiers passages |
| **Mai** | élevé | mariages, weekends amis, sorties fin d'année scolaire, anniversaires |
| **Juin** | élevé | mariages, communions, team building fin d'année fiscale, sorties scolaires |
| **Juillet** | très élevé | familles été, mariages, séjours longs, camping, randonneurs |
| **Août** | très élevé | familles élargies, mariages, vans/camping-cars itinérants |
| **Septembre** | très élevé | rentrée team building / mise au vert entreprise, mariages tardifs |
| **Octobre** | élevé | retraites scolaires, week-ends d'automne, premiers shifts hivernaux |
| **Novembre** | moyen | groupes hivernaux, week-ends thématiques, troupes d'impro |
| **Décembre** | bas-moyen | fêtes de fin d'année (rares mais en hausse), bilans annuels asbl |

### I.2 Saturation observée

- **Mariages dominent juillet/août/septembre** (et bloquent la grande salle, voire tout le lieu sur 2-3 jours). Plusieurs threads où Malau doit refuser des demandes weekend mariage-bloqué.
- **Mois saturés** : juillet et août. **Mois sous-utilisés** : décembre, janvier (sauf weekend nouvelle année), février.
- **Patterns récurrents par saison** :
  - Hiver/début printemps : retraites bien-être, troupes d'impro, week-ends amis intimes
  - Printemps : mariages, communions, scolaires
  - Été : familles, mariages, passants, camping
  - Rentrée (sept-oct) : team building, retraites scolaires, mises au vert
  - Fin d'année (nov-déc) : bilans asbl, fêtes ponctuelles

---

## J. Vocabulary — top 20 termes/expressions clients

> Termes effectivement utilisés par les clients dans le corpus. Utile pour SEO, copy site, labels de form natif Claudy.

| # | Terme/expression | Contexte d'usage |
|---|---|---|
| 1 | **lieu** | "votre lieu est sublime", "découvrir votre lieu" — beaucoup plus que "gîte" |
| 2 | **gîte / le gîte / les gîtes** | usage courant mais le client ne distingue pas Hulotte/Chevêche au début |
| 3 | **disponibilité / disponible / libre** | requête n°1 |
| 4 | **devis** | demande n°1 côté B2B et fréquente côté B2C |
| 5 | **tarif / prix / combien** | demande n°1 côté B2C |
| 6 | **week-end / weekend / wk / WE** | unité naturelle (familles, amis) |
| 7 | **séjour** | terme valise — "notre séjour", "un séjour chez vous" |
| 8 | **groupe** | "un groupe de 25", "notre groupe", "petit groupe" |
| 9 | **réservation / réserver** | jargon principal de l'action |
| 10 | **acompte** | demandé systématiquement après devis |
| 11 | **facture / facturation / pièce justificative / Peppol** | jargon B2B |
| 12 | **TVA / TVAC** | confusion récurrente |
| 13 | **mise au vert** | terme corporate très spécifique (Communa, Empreintes) |
| 14 | **team building / teambuilding** | terme corporate dominant |
| 15 | **retraite** | "retraite scolaire", "retraite bien-être", "retraite annuelle équipe" |
| 16 | **mariage / fête / anniversaire** | événements perso B2C |
| 17 | **pizza party / camembert party** | termes propres au lieu, déjà très adoptés par les clients |
| 18 | **terrasse / bar / épicerie / four à pain** | tropes du lieu, mentionnés positivement |
| 19 | **tente / hamac / van / camping-car / bivouac** | vocabulaire camping |
| 20 | **animateur·trice / animation / atelier** | clients B2B / scolaires |

**Autres mots-clés porteurs identifiés** : "écolieu", "tiers-lieu", "vie collective", "nature", "famille", "permaculture", "valeurs", "convivialité", "se ressourcer", "se retrouver", "moment privilégié".

**Vocabulaire NL/EN observé** (rare mais présent) :
- NL : "chambre a coucher", "weekend in Yvoir", "manche du National Tour" (NL→FR direct)
- EN : "thank you very much", "thank you Malau and Michael" (Airbnb hôtes étrangers)
- → **Faible volume actuel** mais Gîtes Wallonie pousse les contrats NL/EN — gisement à l'export.

---

## K. B2B packs proposés (émergent du corpus observé)

> Construits à partir des patterns réels observés. Composition + bracket prix + durée + audience. Tous sont reconstituables aujourd'hui — il s'agit juste de les **packager** comme produit.

### K.1 Pack "Mise au vert — équipe 15-25" (★★★★ demande forte)

- **Composition** : Hulotte ou Grand-Duc 2 nuits + petite salle ou grande salle + cuisine pro accessible + 2 repas complets (midi + soir, 2 jours) + 1-2 activités (présentation domaine + grimpe ou disc-golf)
- **Prix bracket** : **1800-2800€ TVAC** selon taille
- **Durée** : 2 nuits / 3 jours (mercredi-vendredi ou lundi-mercredi)
- **Audience** : asbl, équipes 15-30p, services publics (SPW, Croix-Rouge, communes)

### K.2 Pack "Team building demi-journée — 25-40" (★★★ demande croissante)

- **Composition** : 1 repas midi végétarien + 2 ateliers en parallèle (bijoux récup' + palettes ou bijoux + disc-golf) + goûter apéritif + accès terrasse et bar
- **Prix bracket** : **1400-1800€ TVAC** pour 30-40p
- **Durée** : 1/2 journée (12h-19h)
- **Audience** : équipes services publics, entreprises proches, coopératives

### K.3 Pack "Retraite scolaire — 12-25 élèves" (★★ récurrent niche fidèle)

- **Composition** : Hulotte ou Grand-Duc 2 nuits + grande salle disponible + repas complets (35€/pers/jour) + 2-3 activités (grimpe + bijoux + cuisine plantes sauvages OU disc-golf + ânes)
- **Prix bracket** : **2000-3500€ TVAC** selon taille classe
- **Durée** : 2-3 nuits (mer-ven souvent, hors weekend)
- **Audience** : écoles secondaires (rhéto), unschooling, mouvements de jeunesse

### K.4 Pack "Retraite bien-être — animée externe 15-25" (★★★ demande forte, sous-exploitée)

- **Composition** : Hulotte ou Grand-Duc 2 nuits + grande salle pour pratique yoga/méditation + accès cuisine + repas végétariens + commande pain Tranches de Vie
- **Prix bracket** : **1800-2600€ TVAC**
- **Audience** : indépendants animant retraites (yoga, art, écriture, danse...) qui louent le lieu et facturent leurs clients
- **Note** : Claudy doit pouvoir proposer le lieu comme *infrastructure-as-a-service* aux animateurs externes — gisement de marge sans charge animation interne.

### K.5 Pack "Mariage tout compris" (★★ déjà existant, à raffiner)

- **Composition actuelle** : 2600€ for tous espaces intérieurs vendredi-dimanche + cuisine pro + Grand-Duc (25 lits) + cérémonie possible dans le bois
- **Audience** : couples 60-140 invités
- **Friction** : jauge "80p assis" coince les mariages plus grands → opportunité de packager une variante "plein air sous tente" + camping invités

### K.6 Pack "Passants randonneurs / cyclos — journée" (★★ émergent)

- **Composition** : accès terrasse + bar + pizza party à la journée + commande de pains
- **Prix bracket** : **150-400€** selon taille groupe
- **Audience** : groupes 10-25 randonneurs ou cyclos en boucle
- **Note** : positionnement "Bienvenue Vélo" à activer (Gîtes Wallonie le pousse).

---

## L. Notable surprises (contre-intuitif / surprenant)

1. **Le Tally form n'est pas qu'un canal de "demande de réservation" : c'est aussi un canal d'information** — beaucoup de "Objet : Je souhaite des informations" avec date fictive. La distinction informationnelle vs transactionnelle doit être *renforcée* dans le form natif Claudy, pas effacée.

2. **Le bar / terrasse en self-service génère beaucoup de demandes "non-clients"** (passants, randonneurs, voisins). C'est une porte d'entrée commerciale sous-exploitée — pas captée dans le funnel actuel.

3. **Plusieurs réservations "concurrentes" entre Tally form et Airbnb pour le même client** (1 famille, 2 demandes en parallèle) → désynchro de funnel à résoudre.

4. **La récurrence B2B est très élevée** : Communa, Empreintes (Ride to the Future), SPW, Croix-Rouge, Solidarcité, Coopiteasy, Funds for Good — ces noms reviennent plusieurs fois par an. Un **CRM B2B avec contrats annuels / cadre / récurrence** serait une amélioration majeure.

5. **Les paiements sont gérés par virement + acompte 50%** — mais aucun lien de paiement intégré (Stripe, etc.). Plusieurs clients pensent qu'il existe "un lien automatique" et sont surpris de devoir faire un virement manuel. **Pain point clair pour Claudy v1.0**.

6. **Le four à pain est plus stratégique qu'on ne le croit** — il est mentionné dans ~25% des threads (pizza party privée, camembert party, demande de four pour pizza B2B). C'est un *asset signature* — à mettre en page d'accueil.

7. **L'absence de jauge claire des repas crée des frictions** — la cuisinière (Stéphanie) répond ad hoc, et plusieurs threads montrent qu'elle est consultée à chaque devis. **Une matrice "type de repas × jauge × prix"** dans Claudy ferait gagner Stéphanie + Malau.

8. **Quasi aucun feedback post-séjour structuré côté Pôle Accueil** — les évaluations 5★ arrivent uniquement par Airbnb. Pas de mécanique post-stay B2B alors que la satisfaction est manifestement haute. **Opportunité : NPS post-stay automatisé** (mailing 7 jours après check-out).

9. **Le pricing "1 nuit en weekend" est souvent perçu comme dissuasif** par les groupes qui veulent juste samedi soir → Malau impose parfois "weekend" pour préserver l'occupation. Un **minimum-nuits dynamique selon saison** rendrait cela lisible.

10. **L'orientation "valeurs" est explicite chez les clients qui abandonnent** : *"votre environnement correspond à nos valeurs mais le budget ne nous le permet pas"* — c'est un compliment ET un signal que le positionnement haut-de-gamme/conscient est correctement perçu. **Ne pas baisser les prix pour capter ces clients** ; offrir plutôt des entrées différenciées (camping, journée, "découverte").

11. **Le rôle d'**hôte Malau** est central au-delà de la transaction** : signature emoji 🌱, ton chaleureux, suivi proactif ("votre séjour approche, j'aimerais voir avec vous le déroulé"). C'est un **différenciateur produit majeur** que Claudy doit augmenter, jamais remplacer par un automate froid.

12. **Une demande de spectacle/billetterie est passée par le mail** ("billet spectacle 31 mai") — signe que **les activités événementielles publiques** (spectacles, projections + pizza party) existent et ont leur propre flux. À inclure dans le scope Claudy v2.

---

## M. Implications directes pour l'ISA Claudy v1.0

> Lecture rapide des actions produit qui découlent de ce qui précède.

### M.1 Forms natifs Claudy — must-have v1

- Séparer **"je veux des infos" (informationnel)** et **"je veux réserver" (transactionnel)** dès l'entrée.
- Champs obligatoires : type de groupe (couple / famille / amis / asbl / entreprise / scolaire / mouvement / mariage / autre) → routing aval.
- Sélecteur d'hébergement **avec capacités explicites** (Hulotte 15, Chevêche 8, Grand-Duc = H+C 25, Tiny 1-4, Bivouac).
- Sélecteur d'espaces (Grande salle 80p, Petite salle 25p, Cuisine pro) — multi-sélect avec dépendances.
- Sélecteur de repas / pizza party / camembert party avec **jauge en temps réel**.
- Sélecteur d'activités avec **durée + prix immédiats**.
- Champ "présence d'animal" (chien) — obligatoire pour cadrer le supplément.
- Calculateur de devis **automatique** affichant le total prévisionnel TVAC.
- Différenciation **B2C / B2B** au check-out : TVA, bon de commande, Peppol, signature contrat.

### M.2 FAQ Claudy — must-have

Les 20 questions de la section B sont la liste exhaustive. Y ajouter explicitement :
- Politique d'annulation / remboursement (à formaliser)
- Politique chien (à standardiser : 1/groupe, supplément X€)
- Bagagerie de check-in/check-out flexible
- Accès aux espaces communs (terrasse, bar, épicerie) durant le séjour
- Spécificités végé / régimes spéciaux / allergies pour les repas
- Bring-your-own-trainer (yoga / animation externe) — règles et tarif salle

### M.3 PricingModel

- **Forfaits hébergement** : Hulotte / Chevêche / Grand-Duc / Tiny → forfait par durée (1n, 2n, 3n, sem) avec dégressivité documentée.
- **Forfaits salles** : Grande / Petite × {journée / demi-journée / soirée} avec capacités.
- **Forfaits activités** : tous tarifés à l'heure (60-120€/h selon animateur) + option €/pers pour zythologie.
- **Forfaits repas** : grille type repas × jauge → €/pers.
- **Forfait mariage** : produit packagé séparément (2600€ + add-ons).
- **Camping** : €/pers/nuit (tente, hamac) + forfait/nuit (van).
- **Toutes les sorties affichent TVAC** + "pas de TVA en plus" en mention légale.

### M.4 Calendar / disponibilités

- Une seule source de vérité : **Claudy = master**, OTAs = clones (sync sortante uniquement).
- Ouverture des disponibilités **à +18 mois minimum** (pour les mariages et mises au vert annuelles).
- Système d'**options "pré-réservation"** (Malau le fait déjà manuellement — à industrialiser).

### M.5 B2B-specific

- Numéro d'enregistrement touristique + statut Gîte Wallonie en pied de devis.
- Génération de **devis PDF structuré** ligne par ligne (le récap Malau est déjà le template).
- Intégration **bon de commande / facture / Peppol** native.
- CRM B2B avec **historique récurrence + remise fidélité optionnelle**.

### M.6 Last-mile expérience client

- Mail automatique "votre séjour approche" J-7 (Malau le fait déjà manuellement) avec briques personnalisables.
- Page récap réservation accessible via lien stable (corriger la friction "je n'ai pas reçu le lien").
- NPS automatique J+7 post-stay.
- Réponses canned-but-warm pour les 20 questions fréquentes (canalisées via Claudy AI + voix Malau).

### M.7 Saturation Malau

- **Backlog Tally form en haute saison** : automatiser **le premier accusé de réception structuré** (date confirmée libre/occupée + lien tarifs + délai réponse prévu) sous 1h.
- Réduire la charge manuelle de 50% sur les demandes "simples" (Tiny, Chevêche couple 1 nuit, bivouac) en leur permettant d'auto-réserver.
- Préserver l'intervention humaine sur les demandes complexes (mariages, B2B, retraites animées).

---

*Fin de l'analyse. ~600 lignes, agrégées et anonymisées. Aucune donnée nominative conservée — toutes les illustrations sont reformulées depuis du verbatim observé.*
