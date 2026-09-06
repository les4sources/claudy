# Un produit portait UNE quantité par personne, partagée par tous ses types :
# les fromages d'un buffet végé (80 g) et ceux d'un buffet avec viande (50 g)
# obligeaient donc à créer deux produits « Fromages ». La quantité devient un
# réglage PAR TYPE — la présence d'une clé dit que le produit concerne ce type.
class AddQuantitiesPerKindToKitchenProducts < ActiveRecord::Migration[8.1]
  def up
    add_column :kitchen_products, :quantities, :jsonb, default: {}, null: false

    # Reprise : la quantité unique devient celle de chacun des types du produit.
    # `trim_scale` évite d'écrire « 80.00 » là où « 80 » suffit.
    execute <<~SQL.squish
      UPDATE kitchen_products SET quantities = COALESCE((
        SELECT jsonb_object_agg(kind, to_jsonb(trim_scale(quantity_per_person)::text))
        FROM jsonb_array_elements_text(kinds) AS kind
      ), '{}'::jsonb)
    SQL

    merge_duplicates!

    remove_index :kitchen_products, :kinds
    remove_column :kitchen_products, :kinds
    remove_column :kitchen_products, :quantity_per_person
    add_index :kitchen_products, :quantities, using: :gin
  end

  def down
    add_column :kitchen_products, :kinds, :jsonb, default: [], null: false
    add_column :kitchen_products, :quantity_per_person, :decimal, precision: 8, scale: 2

    # La quantité redevient unique : on garde la plus grande, celle qui ne fera
    # jamais acheter trop peu. Les produits fusionnés, eux, restent fusionnés.
    execute <<~SQL.squish
      UPDATE kitchen_products SET
        kinds = COALESCE((SELECT jsonb_agg(key) FROM jsonb_object_keys(quantities) AS key), '[]'::jsonb),
        quantity_per_person = COALESCE((
          SELECT MAX(value::numeric) FROM jsonb_each_text(quantities) AS q(key, value)
        ), 1)
    SQL

    change_column_null :kitchen_products, :quantity_per_person, false
    remove_index :kitchen_products, :quantities
    remove_column :kitchen_products, :quantities
    add_index :kitchen_products, :kinds, using: :gin
  end

  private

  # Les doublons créés pour contourner la quantité unique — même nom, même
  # unité, même état — se recollent en une seule ligne. On ne fusionne que si
  # les types ne se contredisent pas : deux quantités différentes sur un même
  # type signeraient deux produits réellement distincts.
  def merge_duplicates!
    rows = select_all(<<~SQL.squish).to_a
      SELECT id, name, unit, note, active, quantities FROM kitchen_products
      ORDER BY position NULLS LAST, id
    SQL

    rows.group_by { |row| [row["name"].to_s.strip.downcase, row["unit"], row["active"]] }.each_value do |group|
      next if group.size < 2

      keeper, *others = group
      merged = quantities_of(keeper)
      absorbed = others.select { |row| mergeable?(merged, quantities_of(row)) }
      next if absorbed.empty?

      absorbed.each { |row| merged = merged.merge(quantities_of(row)) }
      note = ([keeper] + absorbed).filter_map { |row| row["note"].presence }.first

      execute("UPDATE kitchen_products SET quantities = #{connection.quote(merged.to_json)}::jsonb, " \
              "note = #{connection.quote(note)} WHERE id = #{keeper['id'].to_i}")
      execute("DELETE FROM kitchen_products WHERE id IN (#{absorbed.map { |row| row['id'].to_i }.join(',')})")
      say "Produits fusionnés : « #{keeper['name']} » absorbe #{absorbed.size} doublon(s)"
    end
  end

  def quantities_of(row)
    value = row["quantities"]
    value.is_a?(String) ? JSON.parse(value) : (value || {})
  end

  def mergeable?(kept, candidate)
    (kept.keys & candidate.keys).all? { |kind| kept[kind].to_d == candidate[kind].to_d }
  end
end
