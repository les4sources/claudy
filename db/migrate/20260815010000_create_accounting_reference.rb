# Référentiel comptable et analytique (issue #177, lot B).
#
# C'est le VOCABULAIRE de la comptabilité : les entités qui possèdent et qui
# doivent, les comptes sur lesquels on impute, les exercices qui bornent le
# temps, les axes qui répondent à « pour quel pôle », et les comptes où l'argent
# se pose vraiment.
#
# Le choix qui commande le reste : le pôle est un AXE, pas un suffixe de compte.
# Winbooks encodait `6011xx` où `xx` désignait le pôle, ce qui multiplie le plan
# comptable par le nombre de pôles et rend illisible toute réorganisation. Ici le
# compte général reste court et l'analytique vit sur sa propre colonne — changer
# le rattachement d'un pôle ne réécrit aucun compte.
class CreateAccountingReference < ActiveRecord::Migration[8.1]
  def change
    # Les trois entités qui coexistent aux 4 Sources : la Société simple qui
    # porte les travaux, la Fondation qui porte le lieu, la SRL qui porte
    # l'activité commerciale. Le régime TVA est porté ici parce qu'il décide de
    # la validité d'une ligne de facture (garde du lot C).
    create_table :legal_entities do |t|
      t.string :name, null: false
      t.string :form, null: false
      t.string :vat_regime, null: false, default: "exempt"
      t.string :vat_number
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :legal_entities, :name, unique: true
    add_index :legal_entities, :deleted_at

    # Le plan comptable. `reconcilable` marque les comptes dont on suit le détail
    # ligne à ligne (clients, fournisseurs, banque) par opposition à ceux qu'on
    # ne lit qu'en masse.
    create_table :general_accounts do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.integer :klass, null: false
      t.string :nature, null: false
      t.boolean :reconcilable, null: false, default: false
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :general_accounts, :code, unique: true
    add_index :general_accounts, :klass
    add_index :general_accounts, :deleted_at

    # L'exercice borne le temps comptable. Sa clôture est ce qui rend une
    # écriture définitivement intouchable — sans lui, « verrouillé » resterait
    # une politesse.
    create_table :fiscal_years do |t|
      t.references :legal_entity, null: false, foreign_key: true
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.string :status, null: false, default: "open"
      t.datetime :closed_at
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :fiscal_years, [:legal_entity_id, :starts_on], unique: true
    add_index :fiscal_years, :deleted_at

    # Le plan analytique court. Un code, un libellé, éventuellement le pôle qui
    # le porte — et surtout AUCUNE colonne « compte par défaut » nulle part :
    # c'est le défaut de Winbooks (un code appliqué en silence, une recette
    # hébergement qui atterrit sur le bar) éliminé par le schéma.
    create_table :analytic_accounts do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.references :team, foreign_key: true
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :analytic_accounts, :code, unique: true
    add_index :analytic_accounts, :deleted_at

    # Là où l'argent se pose vraiment. Le compte général de contrepartie est
    # obligatoire : un compte de trésorerie sans imputation ne sert à rien.
    create_table :cash_accounts do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.string :iban
      t.references :legal_entity, null: false, foreign_key: true
      t.references :general_account, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :cash_accounts, :name, unique: true
    add_index :cash_accounts, :deleted_at

    # Deux niveaux de pôles, pas trois : un pôle analytique fin sous un pôle
    # économique ou un service support. La contrainte de profondeur est tenue
    # par le modèle — un parent qui a lui-même un parent est invalide.
    add_column :teams, :parent_id, :bigint
    add_column :teams, :kind, :string
    add_column :teams, :analytic_code, :string
    add_index :teams, :parent_id
    add_index :teams, :analytic_code, unique: true
    add_foreign_key :teams, :teams, column: :parent_id

    # Le pré-requis bloquant de « validation par les sourciers du pôle » (lot C) :
    # aujourd'hui personne ne sait, en base, qui appartient à quel pôle.
    create_table :team_memberships do |t|
      t.references :team, null: false, foreign_key: true
      t.references :human, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :team_memberships, [:team_id, :human_id], unique: true
    add_index :team_memberships, :deleted_at
  end
end
