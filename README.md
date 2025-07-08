# Claudy

Claudy is the in-house web application for Les 4 Sources, a foundation whose activities are run by a collective of families living in Yvoir, Belgium, at the Domaine d'Ahinvaux.
[Read more](https://github.com/les4sources/claudy/wiki) in the wiki.

It is built on Ruby on Rails 7 and PostgreSQL.

## Ruby version

See [.ruby-version](https://github.com/les4sources/claudy/blob/main/.ruby-version) and
[.tool-versions](https://github.com/les4sources/claudy/blob/main/.tool-versions).

## Tests

There are no tests for now. We only have a few users and we know each other. If there is a bug, they'll knock at my door!

## Deployment

We deploy on a Akamai/Linode 2GB using Hatchbox. We might set a staging environment up on the same VPS once we start working collectively on the code.

## Quick Start

Beforehand, get the encryption key for the `development` environment and add it to `config/credentials/development.key`.

Then install Ruby 3.1.2 and NodeJS 18.8.0.

Get the default environment variables values and add them to `.env`, or - for now - duplicate `.env.example` to `.env`.

And everything should go like a couque.

```
git clone git@github.com:les4sources/claudy.git
cd claudy
gem install bundler:2.3.19
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
