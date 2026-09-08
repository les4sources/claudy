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

## Tâches planifiées (cron Hatchbox)

Claudy envoie plusieurs emails par des tâches rake idempotentes, lancées par le cron de Hatchbox. Toutes sont sans effet si on les rejoue : elles horodatent ce qu'elles ont envoyé.

| Tâche | Cadence | Ce qu'elle fait |
|---|---|---|
| `bundle exec rake activity_emails:send` | quotidienne | Invitation à choisir ses activités, ~30 jours avant l'arrivée. |
| `bundle exec rake activity_emails:balance_reminder` | quotidienne | Relance du solde exigible, ~14 jours avant l'arrivée. |
| `bundle exec rake coworking:send_expiry_reminders` | quotidienne | Rappel d'expiration des packs de coworking. |
| `bundle exec rake kitchen:weekly_digest` | **vendredi 07:00** | Programme cuisine des 14 prochains jours, un email par responsable. |
| `bundle exec rake kitchen:bread_reminders` | **quotidienne 07:00** | Rappel de commander le pain, 5 jours avant chaque prestation acceptée. |

Fuseau horaire des crons : **Europe/Brussels**.

Le digest se garde d'un double envoi par **semaine ISO** (clé `Setting` `kitchen.digest_last_sent_on`) : le relancer le samedi n'envoie rien. `FORCE=1 bundle exec rake kitchen:weekly_digest` passe outre, pour les essais.
