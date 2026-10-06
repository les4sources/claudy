# Claudy

Claudy is the in-house web application for Les 4 Sources, a foundation whose activities are run 
by a collective of families living in Yvoir, Belgium, at the Domaine d'Ahinvaux.
[Read more](https://github.com/les4sources/claudy/wiki) in the wiki.

It is built on Ruby on Rails 7 and PostgreSQL.

## Ruby version

See [.ruby-version](https://github.com/les4sources/claudy/blob/main/.ruby-version) and
[.tool-versions](https://github.com/les4sources/claudy/blob/main/.tool-versions).

## Tests

There are no tests for now, but we want to introduce a test suite with the upcoming Spaces 
refactoring (see [#8](https://github.com/les4sources/claudy/issues/8)). Feel free to start 
using any test system that you feel comfortable with.

## Deployment

We deploy on a Akamai/Linode 2GB using Hatchbox. We might set a staging environment up on the same VPS
once we start working collectively on the code.

## Quick Start

Beforehand, get the encryption key for the `development` environment and add it to `config/credentials/development.key`.

Then install Ruby 3.4.10 and NodeJS 18.8.0.

Get the default environment variables values and add them to `.env`, or - for now - duplicate `.env.example` to `.env`.

And everything should go like a couque.

```
git clone git@github.com:les4sources/claudy.git
cd claudy
gem install bundler:2.6.9
bundle config build.nio4r --with-cflags="-Wno-incompatible-pointer-types"
bundle install
yarn install
brew install vips
rails db:create && rails db:migrate
rails db:seed
bin/vite dev &
rails s
```

Then use the Rails console to add a first user.

```
> User.create email: "[set email here]", password: "[set password here]"
```

You are ready to go! Open localhost:3000 and have fun!

### Seeding database

Use `rails db:seed` to add lodgings, rooms and spaces to the database.

### Sending emails

Emails are delivered using Postmark. Please ask Michael (it@les4sources.be) for credentials.

### Flux iCal des gardes (Google Agenda)

Les gardes (rôle « Veilleur·euse ») sont publiées sous forme de flux iCalendar
abonnable, pour qu'elles apparaissent dans l'agenda personnel de chacun·e sans
avoir à ouvrir Claudy.

**S'abonner depuis Google Agenda**

1. Dans Google Agenda : *Autres agendas* → **+** → **Ajouter à partir de l'URL**.
2. Coller `https://app.les4sources.be/watchman.ics?token=LE_JETON`.
3. Valider. Google re-synchronise le flux tout seul (comptez plusieurs heures
   entre deux rafraîchissements — c'est Google qui décide, pas nous).

Le flux est en **lecture seule** et **collectif** : un seul événement journée
entière par jour, titré `Garde : Ana & Bruno` quand plusieurs personnes sont de
garde le même jour. Seuls les **titulaires** y figurent (les `backup` non), et
tout l'historique est exporté. Chaque événement renvoie vers le calendrier
Claudy du mois concerné.

**Le jeton**

L'URL n'est protégée que par le jeton `?token=…`, comparé en temps constant à la
variable d'environnement `WATCHMAN_ICS_TOKEN`. Toute requête sans jeton, avec un
mauvais jeton, ou lorsque la variable n'est pas configurée reçoit un **404** : le
flux n'est jamais ouvert par défaut. Le jeton vaut donc accès en lecture aux noms
et aux dates de garde — il se transmet à la main, pas en clair sur le web.

Générer un jeton : `ruby -rsecurerandom -e 'puts SecureRandom.urlsafe_base64(32)'`.

> ⚠️ **Déploiement Hatchbox.** Après avoir ajouté ou changé `WATCHMAN_ICS_TOKEN`,
> il faut un **vrai redémarrage** de l'app, pas un simple déploiement : le
> hot-reload (SIGUSR2) ne recharge pas l'environnement, et la route continuerait
> de renvoyer 404 alors que la variable semble bien configurée.

### Orthophoto partagée avec Semisto Designer

Semisto Designer affiche l'orthophoto du domaine comme « vue drone » de la carte
des 4 Sources. Son navigateur lit les tuiles chez Claudy, sans session, avec le
jeton `?partage=…` comparé en temps constant à `MAP_TILES_SHARE_TOKEN`. Le jeton
n'ouvre que la photo (`rgb`), jamais le relief ni la page Carte ; sans variable,
rien n'est ouvert, et la vider révoque le partage. L'en-tête CORS n'est posé que
pour les origines de `MAP_TILES_SHARE_ORIGINS` (défaut `https://designer.semisto.org`).

Adresse à coller dans Designer (`/admin/drone-views`, format « Tuiles XYZ ») :
`https://<hôte de Claudy>/map/tiles/<clé de la couche>/rgb/{z}/{x}/{y}.png?partage=<jeton>`.
Même remarque que plus haut : un vrai redémarrage sur Hatchbox après avoir posé la variable.

## API publique et publication sur le site les4sources.be

Le site public (repo `les4sources/les4sources-website`, Astro statique) lit Claudy **au build**, sans authentification, sur trois endpoints en lecture seule, cacheables cinq minutes avec ETag, sans aucune donnée personnelle. Le contrat de référence est `docs/CLAUDY.md` du repo du site.

| Endpoint | Contenu |
|---|---|
| `GET /api/public/v1/events?from=&to=` | événements publiés (défaut : depuis un an), avec catégorie, résumé, description publique, lieu, prix, lien d'inscription, image |
| `GET /api/public/v1/experiences` | activités publiées, prix, porteur (prénom seul), créneaux à venir sur six mois avec places restantes |
| `GET /api/public/v1/event_categories` | catégories avec `slug`, couleur hex et pôle de la charte |

**Publier.** Un événement ou une activité est un brouillon tant que `published_at` est vide : rien n'en sort. Le bouton « Publier sur le site » (fiche de l'événement ou de l'activité) pose `published_at` et le `slug` — proposé depuis le titre et le mois (`pizza-party-septembre-2026`), modifiable dans le formulaire jusqu'à la publication, figé tant que la fiche est en ligne. « Dépublier » retire la fiche du site et garde le slug. Sur une catégorie, le pôle de la charte (sept valeurs) donne la couleur et le pictogramme des cartes ; la couleur est un hex.

**Dupliquer.** « Dupliquer » sur un événement ouvre le formulaire de création prérempli (titre, résumé, description publique, catégorie, lieu, prix, lien, image) sans dates ni slug : rien n'est écrit avant « Enregistrer », et la copie reste un brouillon.

**Reconstruction du site.** Toute sauvegarde d'une fiche publiée (ou sa publication, dépublication, suppression) enfile `WebsiteRebuildJob`, qui regroupe les demandes sur deux minutes puis fait un `POST` sur `WEBSITE_REBUILD_WEBHOOK_URL` (webhook de déploiement Coolify ou `repository_dispatch` GitHub), avec `Authorization: Bearer WEBSITE_REBUILD_WEBHOOK_TOKEN` si le jeton est renseigné. Sans URL, le job journalise et ne fait rien ; hors production il ne fait rien non plus, sauf `WEBSITE_REBUILD_ALLOW_NON_PRODUCTION=1`.

## Pizza Party de Tranches de Vie

Une Pizza Party privée réservée et payée sur **Tranches de Vie** (repo `les4sources/tranchesdevie2`) est souvent liée à un séjour de groupe géré ici. Quand le séjour est facturable, la party doit figurer sur sa facture. Depuis la fiche séjour, le bloc « Pizza Party » (sous les paiements) liste les parties privées **payées** autour des dates du séjour et permet d'en rattacher une.

Le rattachement est **manuel** et la relation est en **lecture seule** : Claudy interroge l'API de Tranches de Vie, ne lui écrit jamais. La party s'ajoute au **Total séjour** et le paiement miroir qu'elle crée (moyen `tranchesdevie`) compte dans l'**Encaissé** — un séjour soldé le reste. Ce paiement ne se modifie ni ne se supprime depuis la liste des paiements : on **détache** la party à la place. Une annulation ou un remboursement décidé là-bas est répercuté ici (la party sort du total, son paiement passe `refunded`), par le bouton « Actualiser » du bloc ou par le passage quotidien.

| Variable | Défaut | Rôle |
|---|---|---|
| `TRANCHESDEVIE_API_URL` | `https://tranchesdevie.les4sources.be` | Base de l'API de Tranches de Vie. |
| `TRANCHESDEVIE_API_KEY` | — | Jeton `Authorization: Bearer`. **Sans elle, aucun appel sortant** : le bouton de rattachement est rendu désactivé avec l'explication. |

Contrat de l'API côté Tranches de Vie : `les4sources/tranchesdevie2#290`.

## Connecteur Claude (serveur MCP)

Claudy expose un serveur MCP à `https://app.les4sources.be/mcp` : branché comme connecteur dans Claude, il fait ce que fait l'interface, domaine par domaine, avec des outils métier écrits à la main (`app/services/mcp/tools/`). Pas d'exécution de code arbitraire.

**Comptes courants.** En lecture : `chercher_comptes`, `diagnostic_compte`, `lignes_compte`, `poste_par_mois`, `virements_recus`, `historique_ligne`. En écriture : `supprimer_lignes` (suppression douce), `contre_passer_lignes`, `passer_ecriture`, `abandonner_dette`, `encoder_reglement`.

**Séjours et clients** (`tools/sejours/`). En lecture : `chercher_sejours`, `fiche_sejour`, `disponibilites`, `devis_sejour`, `chercher_clients`, `fiche_client`. En écriture : `creer_sejour`, `modifier_sejour`, `changer_statut_sejour`, `preconfirmer_sejour`, `refuser_sejour`, `renvoyer_confirmation`, `traiter_demande_modification`, `noter_sejour`, `enregistrer_paiement_sejour`, `modifier_paiement_sejour`, `supprimer_sejour`, `modifier_client`. Ils passent par les mêmes services que les écrans (`Reservations::Builder`, `Stays::AdminUpdater`, `Stays::QuickStatusUpdater`…) ; ceux qui envoient un email au client le disent dans leur description et dans leur aperçu.

**Activités** (`tools/activites/`). En lecture : `chercher_activites`, `fiche_activite`, `reservations_activites` (à valider, tenue à déclarer). En écriture : `ajouter_activite_sejour`, `modifier_reservation_activite`, `annuler_reservation_activite`, `valider_reservation_activite`, `refuser_reservation_activite`, `declarer_tenue`, `creer_creneau`, `supprimer_creneau`, `enregistrer_activite`, `publier_activite`. Un porteur restreint n'y voit que ses activités, comme dans l'interface ; les gestes réservés à l'équipe lui sont refusés.

**Cuisine** (`tools/cuisine/`). En lecture : `prestations_cuisine` (les onglets de la page Cuisine), `fiche_prestation` (avec la liste de courses), `bilan_cuisine`, `reglages_cuisine`. En écriture : `commander_prestations`, `modifier_prestation`, `changer_statut_prestation`, `repondre_prestation` (accepter, refuser, se désister), `confier_prestation`, `rattacher_prestation`, `enregistrer_produit_cuisine`, `modifier_reglages_cuisine`. Fermés aux porteurs restreints, comme la page Cuisine. Contrairement à la page, chaque geste recalcule le total du séjour.

**Vie du collectif** (`tools/collectif/`). En lecture : `rassemblements`, `fiche_rassemblement` (ordre du jour, notes de réunion, actions, décisions, compte rendu), `decisions` (registre), `cycle_collectif` (charge de chacun), `actions_membre`, `roles_du_jour` (veille et ligne de garde). En écriture : `enregistrer_rassemblement`, `point_odj`, `action_rassemblement`, `enregistrer_decision`, `commenter` (notifie la conversation), `enregistrer_action_cycle`, `geste_action_cycle` (cocher, fois, heures réelles, reporter, passer ou copier au cycle suivant, archiver…), `objectif_cycle`, `cloturer_cycle`, `attribuer_role`. Fermés aux porteurs restreints. Les points et décisions sont signés du membre rattaché au compte ; un compte sans membre est refusé plutôt que de signer au nom d'un autre.

**Finances** (`tools/finances/`). En lecture : `tresorerie` (soldes, À affecter, À payer, projection à 90 jours), `lignes_tresorerie` (la file « À affecter » et le journal, avec ses filtres), `fiche_ligne_tresorerie` (affectations, suggestion, pistes de rapprochement), `referentiel_comptable` (plan, pôles, entités, motifs de caisse, tiers…), `factures_achat`, `notes_de_frais`, `a_payer`, `feuille_de_caisse`, `decomptes`, `batch_cooking`, `arrete_du_mois`. En écriture : `affecter_ligne` (une ou plusieurs parts, comptabilisée dès qu'elle est couverte), `rapprocher_ligne` (facture d'achat, note de frais, règlement ou virement d'un membre, séjour, facture de vente, versement Stripe), `geste_ligne_tresorerie` (suggestion, comptabiliser, annuler la passation, exclure, retirer une affectation), `enregistrer_facture_achat`, `geste_facture_achat` (soumettre, valider, contester, rouvrir, payer en espèces), `enregistrer_note_de_frais`, `geste_note_de_frais`, `ligne_caisse`, `generer_charges_recurrentes`, `decompte` (émettre, envoyer, relancer, marquer réglé), `enregistrer_batch_cooking`, `arreter_mois`. Fermés aux porteurs restreints. Les pièces (PDF des factures, justificatifs des notes) se déposent dans Claudy ; l'import CODA, le comptage de caisse et le paramétrage de la compta (plan, règles, tiers, exercices) restent à l'écran.

**Aperçu puis confirmation.** Un outil d'écriture n'écrit jamais au premier appel : il décrit ce qu'il ferait, avec ce que le compte devra encore après, et rend un code de confirmation signé (15 minutes). Rappelé avec ce code, il recalcule le plan et refuse s'il a changé. Tout est signé dans PaperTrail `claude:<e-mail> — <motif>`.

**Connexion.** OAuth 2.1 avec PKCE et enregistrement dynamique du client : Claude ouvre la page « Brancher Claude sur Claudy », on s'y connecte avec son compte Claudy et on autorise. Seules les adresses de retour de Claude (`claude.ai`, `claude.com`, `localhost`) sont acceptées. Jeton d'accès d'une heure, rafraîchissement de trente jours qui tourne à chaque usage ; supprimer les lignes de `mcp_tokens` coupe l'accès.

| Variable | Défaut | Rôle |
|---|---|---|
| `MCP_ALLOWED_EMAILS` | — | Comptes Claudy autorisés à brancher Claude, séparés par des virgules. **Vide = personne.** Retirer une adresse coupe ses jetons sur-le-champ. |
| `MCP_BASE_URL` | `https://<hôte de la requête>` | Adresse publique annoncée dans les métadonnées OAuth, si elle diffère. |

**Ajouter le connecteur** : dans Claude, Personnaliser → Connecteurs → « Ajouter un connecteur personnalisé », URL `https://app.les4sources.be/mcp`, sans identifiants OAuth (Claude s'enregistre seul). En ligne de commande : `claude mcp add --transport http claudy https://app.les4sources.be/mcp`.

## Tâches planifiées (cron Hatchbox)

Claudy envoie plusieurs emails par des tâches rake idempotentes, lancées par le cron de Hatchbox. Toutes sont sans effet si on les rejoue : elles horodatent ce qu'elles ont envoyé.

| Tâche | Cadence | Ce qu'elle fait |
|---|---|---|
| `bundle exec rake activity_emails:send` | quotidienne | Invitation à choisir ses activités, ~30 jours avant l'arrivée. |
| `bundle exec rake activity_emails:balance_reminder` | quotidienne | Relance du solde exigible, ~14 jours avant l'arrivée. |
| `bundle exec rake coworking:send_expiry_reminders` | quotidienne | Rappel d'expiration des packs de coworking. |
| `bundle exec rake kitchen:weekly_digest` | **vendredi 07:00** | Programme cuisine des 14 prochains jours, un email par responsable. |
| `bundle exec rake kitchen:bread_reminders` | **quotidienne 07:00** | Rappel de commander le pain, 5 jours avant chaque prestation acceptée. |
| `bundle exec rake finance:deadline_reminders` | **quotidienne 07:00** | Échéancier comptable : génère les échéances des 12 prochains mois, puis rappelle chaque échéance ouverte à J-14, J-3 et en retard (chaque semaine). Destinataire : le responsable de l'obligation, à défaut les destinataires comptables des réglages. |
| `bundle exec rake tranches_de_vie:sync_parties` | quotidienne | Répercute les annulations et remboursements des Pizza Party depuis Tranches de Vie. Sans effet si `TRANCHESDEVIE_API_KEY` est absente. |

Fuseau horaire des crons : **Europe/Brussels**.

Ces tâches mettent leurs emails en file (`deliver_later`) sur l'adaptateur `:async` : le processus attend que la file soit vide avant de sortir (`config/initializers/active_job_async_drain.rb`). Sans cette attente, les derniers emails d'un passage partaient avec le processus, déjà horodatés comme envoyés.

Le digest se garde d'un double envoi par **semaine ISO** (clé `Setting` `kitchen.digest_last_sent_on`) : le relancer le samedi n'envoie rien. `FORCE=1 bundle exec rake kitchen:weekly_digest` passe outre, pour les essais.
