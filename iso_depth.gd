## iso_depth.gd
## İzometrik ızgara için merkezi z-index hesaplama yardımcısı.
## Oyundaki TÜM nesneler (blok, karakter, duvar, efekt…) bu sınıfı kullanır.
##
## ═══════════════════════════════════════════════════════
##  GÖRÜNÜRLÜK SIRALAMASININ 3 KURALI  (öncelik sırası)
## ═══════════════════════════════════════════════════════
##
##  KURAL 1 — Konum (en güçlü)
##    D = cell.x + cell.y   (büyük D = güneye yakın = kameraya yakın = önde)
##    Her D birimi STRIDE kadar z-index ekler → komşu hücreler kesinlikle ayrılır.
##    Yükseklik de bu hesaba girer: D_efektif = D + elevation
##
##  KURAL 2 — Yükseklik (aynı konum, farklı irtifa)
##    Daha yüksek nesne önde.
##    Uygulama: eb = elevation * STRIDE  →  z += eb
##    Böylece 1 birim yükseklik = 1 birim güneye eşdeğer derinlik.
##
##  KURAL 3 — Nesne tipi (aynı konum + aynı yükseklik)
##    Aynı D'deki nesneler arası slot sırası (küçükten büyüğe = arkadan öne):
##
##      D*STRIDE − 1  →  NE/NW duvar  |  blok üst yüzü
##      D*STRIDE + 0  →  blok sağ (doğu) yüzü
##      D*STRIDE + 1  →  karakter  (yön kuralından muaf)
##      D*STRIDE + 2  →  SW/SE duvar  |  blok ön (güney) yüzü
##      D*STRIDE + 3  →  blok üst kenarlık  (border)
##
##    Duvar yön kuralı:
##      SW (ön yüz) / SE (sağ yüz) → slot +2  →  karakterin önünde
##      NE (kuzey)  / NW (batı)    → slot −1  →  karakterin arkasında
##    Karakter her zaman slot +1 → yön kuralından bağımsız orta konumda.
##
## ═══════════════════════════════════════════════════════
##  DERINLIK FORMÜLLERI  (blok yüzleri için)
## ═══════════════════════════════════════════════════════
##
##  Blok ön (güney) yüzü :  d = (cx+dx) + (cy+sy−2)   ← karakter önde kalsın diye −1 kaydır
##  Blok sağ (doğu) yüzü :  d = (cx+sx−1) + (cy+dy)
##  Blok üst yüzü        :  d = (cx+dx)   + (cy+dy)    (hücre başına)
##
##  SW duvar ön yüzü     :  d = (cx+dx) + (cy+sy−1)   ← gerçek güney kenar (bloktan +1 fazla)
##  SE duvar sağ yüzü    :  d = (cx+sx−1) + (cy+dy)
##  NE duvar kuzey yüzü  :  d = (cx+dx) + cy
##  NW duvar batı yüzü   :  d = cx + (cy+dy)
##
## ═══════════════════════════════════════════════════════
##  KULLANIM
## ═══════════════════════════════════════════════════════
##
##   # Tek hücreli nesne (karakter, küçük prop, efekt):
##   z_index = IsoDepth.single(grid_x, grid_y)
##
##   # Blok / duvar görseli → _build_block_visuals() / _build_wall_visuals() içinde
##   # her yüz poligonu için ayrı d hesaplanır; z = d * STRIDE + slot + eb

class_name IsoDepth

const STRIDE := 4   # Her D birimi için ayrılan z-index aralığı (slot sayısı = 5: −1…+3)

# ── Tek hücreli nesne (karakter, 1×1 eşya, efekt) ───────────────────────────

## Karakterin veya 1×1 nesnenin z_index'i.  Slot +1 (Kural 3 orta).
static func single(gx: int, gy: int) -> int:
	return (gx + gy) * STRIDE + 1

# ── Blok yüzleri için yardımcı (geriye dönük uyumluluk) ─────────────────────

## Blok sağ (doğu) yüzü — slot 0.
static func east_face(cx: int, cy: int, sx: int, _sy: int) -> int:
	return (cx + sx - 1 + cy) * STRIDE + 0

## Blok ön (güney) yüzü — slot +2, d'de −1 kaydırma (karakter önde kalsın).
static func south_face(cx: int, cy: int, _sx: int, sy: int) -> int:
	return (cx + cy + sy - 2) * STRIDE + 2

## SW duvar ön yüzü — slot +2, gerçek güney kenar (cy+sy−1).
static func wall_south_face(cx: int, cy: int, _sx: int, sy: int) -> int:
	return (cx + cy + sy - 1) * STRIDE + 2

## Blok üst kenarlık (border) — en güneydoğu köşe, slot +3.
static func top_border(cx: int, cy: int, sx: int, sy: int) -> int:
	return (cx + sx - 1 + cy + sy - 1) * STRIDE + 3
