module Mcp
  module Tools
    module Finances
      # Un compte de trésorerie (banque, caisse) : le créer ou le corriger
      # (Michael, 2026-10-14, compte épargne de la fondation). Jusqu'ici seule
      # l'API (`Api::V1::CashAccountsController`) le pouvait, et un import CODA
      # qui ne trouve pas l'IBAN refuse le fichier : sans IBAN, un compte ne
      # reçoit aucun relevé.
      #
      # L'entité et la contrepartie générale ne bougent plus dès que le compte
      # porte des lignes : leurs écritures sont déjà passées sur l'une et
      # l'autre, et les changer en dessous mentirait au grand livre.
      class CompteTresorerie < Ecriture
        include Commun

        NATURES = { "banque" => "bank", "caisse" => "cash" }.freeze

        tool "compte_tresorerie",
             title: "Créer ou corriger un compte de trésorerie",
             description: "Un compte où l'argent se pose (banque, caisse) : nom, IBAN, entité, compte général de " \
                          "contrepartie (550000…), actif. L'IBAN est ce qui relie un relevé CODA ou un export Beobank au " \
                          "compte : sans lui, l'import refuse le fichier. Deux comptes ne portent jamais le même IBAN. " \
                          "L'entité et le compte général ne changent plus une fois que le compte a des lignes. Les " \
                          "comptes Stripe se règlent avec mode_stripe. La liste : parametrage_compta entites.",
             schema: {
               properties: {
                 compte: { type: %w[integer string], description: "Pour corriger : le compte (nom ou #id). Absent : nouveau compte." },
                 nom: { type: "string" },
                 iban: { type: "string", description: "IBAN (« BE57 5230 4480 0335 »). Chaîne vide pour l'effacer." },
                 nature: { type: "string", enum: NATURES.keys, description: "Défaut à la création : banque." },
                 entite: ENTITE.merge(description: "Entité qui possède le compte. Défaut à la création : la fondation."),
                 compte_general: COMPTE_GENERAL.merge(description: "Compte de contrepartie, classe 5 (550000, 550002…)."),
                 active: { type: "boolean" }
               }
             }

        private

        def planifier(arguments)
          compte = arguments["compte"].present? ? par_nom!(CashAccount.all, arguments["compte"], "compte de trésorerie") : nil
          raise Error, "#{compte.name} est un compte Stripe : il se règle avec mode_stripe." if compte&.stripe?

          attributs = attributs!(arguments, compte)
          raise Error, "Rien à changer." if compte && attributs.empty?

          verifier_iban!(attributs[:iban], compte) if attributs.key?(:iban)
          verifier_lignes!(compte, attributs) if compte

          apres = simuler { ecrire(compte&.id, attributs) }
          resume = compte ? "Corriger : #{ligne_compte(compte)}\nAprès : #{apres}" : "Nouveau compte : #{apres}"
          resume += "\nLes relevés CODA et les exports Beobank de cet IBAN entreront sur ce compte." if attributs[:iban].present?
          Plan.new(resume: resume, empreinte: [compte && etat_de(compte), attributs.transform_values(&:to_s).sort],
                   donnees: { id: compte&.id, attributs: attributs })
        end

        def appliquer(plan)
          "Compte de trésorerie enregistré : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          compte = id ? CashAccount.find(id) : CashAccount.new
          metier! { compte.update!(attributs) }
          ligne_compte(compte.reload)
        end

        def ligne_compte(c)
          "##{c.id} #{c.name} · #{c.kind_label} · IBAN #{c.iban.presence || 'aucun'} · #{c.legal_entity&.name} · " \
            "#{c.general_account}#{' · INACTIF' unless c.active?}"
        end

        def attributs!(arguments, compte)
          a = {}
          a[:name] = arguments["nom"].to_s.strip if arguments["nom"].present?
          a[:iban] = iban(arguments["iban"]) if arguments.key?("iban")
          a[:kind] = NATURES[arguments["nature"]] || raise(Error, "nature : #{NATURES.keys.join(' ou ')}.") if arguments["nature"].present?
          a[:legal_entity_id] = entite!(arguments["entite"]).id if arguments["entite"].present?
          a[:general_account_id] = contrepartie!(arguments["compte_general"]).id if arguments["compte_general"].present?
          a[:active] = arguments["active"] unless arguments["active"].nil?
          a = a.reject { |cle, valeur| compte.public_send(cle) == valeur } if compte
          return a if compte

          raise Error, "Pour créer un compte, donne son nom." if a[:name].blank?
          raise Error, "Pour créer un compte, donne son compte général (550000…)." if a[:general_account_id].nil?

          fondation = LegalEntity.actives.find_by(form: "foundation")
          { kind: "bank", legal_entity_id: fondation&.id }.merge(a)
        end

        # Rangé par groupes de quatre, comme la banque l'imprime : l'import
        # compare les chiffres, la forme ne compte que pour qui le lit.
        def iban(valeur)
          brut = valeur.to_s.gsub(/[^A-Za-z0-9]/, "").upcase
          return nil if brut.empty?
          raise Error, "IBAN illisible : « #{valeur} »." unless brut.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{8,30}\z/)

          brut.scan(/.{1,4}/).join(" ")
        end

        def contrepartie!(reference)
          compte = compte_general!(reference)
          raise Error, "#{compte} n'est pas un compte de trésorerie (classe 5)." unless compte.klass == 5

          compte
        end

        # Un IBAN porté par deux comptes, et l'import refuse les deux.
        def verifier_iban!(valeur, compte)
          return if valeur.nil?

          chiffres = valeur.gsub(/\D/, "")
          doublon = CashAccount.with_deleted { CashAccount.where.not(id: compte&.id).to_a }
                                .find { |c| c.iban.to_s.gsub(/\D/, "") == chiffres }
          raise Error, "L'IBAN #{valeur} est déjà porté par « #{doublon.name} »." if doublon
        end

        def verifier_lignes!(compte, attributs)
          bloques = { legal_entity_id: "l'entité", general_account_id: "le compte général" }.select { |cle, _| attributs.key?(cle) }
          return if bloques.empty?

          lignes = CashEntry.with_deleted { CashEntry.where(cash_account_id: compte.id).count }
          return if lignes.zero?

          raise Error, "#{compte.name} porte #{lignes} ligne(s) déjà passées : #{bloques.values.join(' et ')} ne change(nt) plus. " \
                       "Crée un autre compte s'il le faut."
        end
      end
    end
  end
end
