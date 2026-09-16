# La note INTERNE du séjour devient une vraie association ActionText
# (`has_rich_text :internal_notes`), et la colonne `stays.notes` disparaît
# — décision de Michael du 2026-09-14, epic #314 phase 2 (issue #313).
#
# Pourquoi supprimer la colonne dans la MÊME migration : deux emplacements pour
# la même note finiraient par diverger, et une colonne qui change de nature en
# silence se paie deux ans plus tard.
#
# La conversion reproduit EXACTEMENT le rendu actuel, qui passait par
# `simple_format` : double saut de ligne → paragraphe, simple → `<br />`, et le
# texte est échappé. Rien ne doit bouger à l'écran pour une note existante.
class MoveStayNotesToRichText < ActiveRecord::Migration[8.1]
  RICH_TEXT_NAME = "internal_notes".freeze

  def up
    copied = 0

    say_with_time "Recopie de stays.notes vers action_text_rich_texts" do
      now = connection.quote(Time.current)

      # `stays` en direct plutôt que le modèle : la migration doit rester
      # indépendante du code de l'application, et les séjours SOFT-DELETED
      # portent des notes qu'une fiche restaurée doit retrouver.
      rows = select_all(<<~SQL.squish)
        SELECT id, notes FROM stays
        WHERE notes IS NOT NULL AND btrim(notes) <> ''
      SQL

      rows.each do |row|
        html = ActionController::Base.helpers.simple_format(row["notes"])

        execute(<<~SQL.squish)
          INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
          VALUES (#{connection.quote(RICH_TEXT_NAME)}, #{connection.quote(html)}, 'Stay', #{row['id'].to_i}, #{now}, #{now})
          ON CONFLICT (record_type, record_id, name) DO NOTHING
        SQL

        copied += 1
      end

      copied
    end

    remove_column :stays, :notes
  end

  # Irréversible : la colonne `stays.notes` contenait du texte brut, les
  # enregistrements ActionText contiennent du HTML. Revenir en arrière
  # demanderait une conversion HTML → texte qui perdrait la mise en forme
  # saisie depuis la migration. Restaurer une sauvegarde, plutôt.
  def down
    raise ActiveRecord::IrreversibleMigration,
          "stays.notes a été convertie en texte riche (ActionText) : le retour " \
          "arrière perdrait toute mise en forme saisie depuis. Restaurer une sauvegarde."
  end
end
