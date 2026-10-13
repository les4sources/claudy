require "digest"

module Mcp
  module Tools
    module Finances
      # Comptabilité > Banque & caisse > CODA (CodaImportsController#create) :
      # déposer un fichier CODA. Le connecteur ne transporte pas de fichier, mais
      # un CODA est du TEXTE (lignes de 128 caractères) : Claude lit le fichier
      # que l'utilisateur lui confie et en passe le contenu tel quel. Même service
      # que l'écran, donc mêmes contrôles bloquants : un fichier refusé ne laisse
      # rien derrière lui, un mouvement déjà importé n'est pas doublé.
      class ImporterCoda < Ecriture
        include Commun

        TAILLE_MAX = 5.megabytes

        tool "importer_coda",
             title: "Déposer un fichier CODA",
             description: "Importe un relevé bancaire CODA (.cod, .txt) dans le journal de trésorerie, comme l'écran " \
                          "CODA : `contenu` = le texte COMPLET du fichier, sans rien retirer ni reformater (lignes de " \
                          "128 caractères, de l'enregistrement 0 au 9). L'aperçu dit combien de lignes seraient créées " \
                          "ou ignorées (déjà présentes), ou pourquoi le fichier serait refusé (relevé qui ne se referme " \
                          "pas, relevé manquant, compte inconnu). Les lignes arrivent « à affecter » : lignes_tresorerie.",
             schema: {
               properties: {
                 contenu: { type: "string", description: "Le texte intégral du fichier CODA." },
                 nom_fichier: { type: "string", description: "Le nom du fichier (ex. « belfius-2026-09.cod »)." }
               },
               required: %w[contenu nom_fichier]
             }

        # Le service tient sa propre transaction, et rien n'y part par email.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          contenu = arguments["contenu"].to_s
          raise Error, "Le contenu du fichier est vide." if contenu.strip.empty?
          raise Error, "Fichier trop gros pour le connecteur (#{contenu.bytesize / 1024} Ko) : dépose-le à l'écran." if contenu.bytesize > TAILLE_MAX

          nom = arguments["nom_fichier"].to_s.strip.presence || raise(Error, "Donne le nom du fichier.")
          rapport = simuler { importer(contenu, nom, "claude:#{user.email}") }
          raise Error, rapport.to_text if rapport.status == "already_imported"

          resume = "Dépôt de « #{nom} » : #{rapport.to_text}"
          resume += "\nRien de nouveau : aucune ligne ne serait créée." if rapport.entries_created.zero?
          Plan.new(resume: resume, empreinte: [Digest::SHA256.hexdigest(contenu), nom],
                   donnees: { contenu: contenu, nom: nom })
        end

        def appliquer(plan)
          rapport = importer(plan.donnees[:contenu], plan.donnees[:nom], whodunnit)
          raise Error, rapport.to_text if rapport.status == "already_imported"

          "Dépôt ##{rapport.coda_import&.id} : #{rapport.to_text}\nLes nouvelles lignes attendent dans « À affecter » (lignes_tresorerie)."
        end

        def importer(contenu, nom, auteur)
          ::Coda::Import.new(content: contenu, filename: nom, whodunnit: auteur).run!
        rescue ::Coda::Import::Rejected, ::Coda::ParseError => e
          raise Error, "Fichier refusé, rien n'a été importé : #{e.message}"
        end
      end
    end
  end
end
