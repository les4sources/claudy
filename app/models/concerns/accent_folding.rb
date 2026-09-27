# Comparer du texte sans tenir compte des accents ni de la casse : « cheveche »
# trouve « la Chevêche », « neflier » trouve « Néflier ».
#
# Sans l'extension `unaccent` (non garantie sur le serveur) : `translate()` est
# natif dans PostgreSQL. La même table de correspondance sert côté SQL (`sql`)
# et côté saisie (`fold`, `pattern`), pour que les deux côtés soient pliés de la
# même façon.
module AccentFolding
  # Les majuscules accentuées sont dans la table aussi : sous une collation « C »,
  # `lower()` de PostgreSQL ne descend pas « É » en « é ».
  LOWER = "àáâãäåāăąçćčďèéêëēėęěìíîïīįłñńňòóôõöøōőùúûüūůűųýÿžźżœæ"
  PLAIN = "aaaaaaaaacccdeeeeeeeeiiiiiilnnnoooooooouuuuuuuuyyzzzoa"
  FROM = LOWER + LOWER.upcase
  TO   = PLAIN + PLAIN
  raise "AccentFolding : tables de longueurs différentes" unless FROM.length == TO.length

  module_function

  # L'expression SQL pliée, à comparer par LIKE à un `pattern`.
  def sql(expression) = "translate(lower(#{expression}), '#{FROM}', '#{TO}')"

  def fold(text) = text.to_s.downcase.tr(FROM, TO)

  # « %chev%che% » échappé pour LIKE, déjà plié.
  def pattern(text) = "%#{ActiveRecord::Base.sanitize_sql_like(fold(text))}%"
end
