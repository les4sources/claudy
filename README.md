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
