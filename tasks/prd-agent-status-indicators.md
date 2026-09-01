# PRD: AI Agent Compact Status Indicators

## 1. Giriş

Claude, Codex ve OpenCode etkinlikleri küçük adada kendi logolarıyla görünür. Bu özellik,
logoyu değiştirmeden agent durumunu tek bakışta anlatan minimalist göstergeler ekler.

Kullanıcı kararları:

- `thinking`, `working` ve `usingTool`: ikon altında ileri–geri hareket eden küçük nokta
- `waitingForUser`: sarı soru işareti
- `error`: kırmızı hata işareti
- `completed`: yeşil tamamlandı işareti; mevcut 5 saniyelik kapanma süresince görünür

## 2. Hedefler

- Agent logosunu koruyarak çalışma ve sonuç durumunu anlaşılır kılmak.
- Claude, Codex ve OpenCode için aynı durum dilini kullanmak.
- Küçük adanın mevcut yüksekliğini ve minimalist görünümünü korumak.
- Çoklu ekranlarda aynı agent için aynı gösterge durumunu göstermek.
- Hareketi Azalt açıkken sürekli hareket üretmemek.
- Agent çalışmıyorken zamanlayıcı veya animasyon maliyeti oluşturmamak.

## 3. Durum Matrisi

| Agent durumu | Küçük ada göstergesi | Hareket | Renk | Süre |
|---|---|---|---|---|
| `idle` | Yok | Yok | — | Durum boyunca |
| `thinking` | İkon altında 3 px nokta | Yatay ileri–geri | Beyaz | Durum boyunca |
| `working` | İkon altında 3 px nokta | Yatay ileri–geri | Beyaz | Durum boyunca |
| `usingTool` | İkon altında 3 px nokta | Yatay ileri–geri | Beyaz | Durum boyunca |
| `waitingForUser` | İkonun sağ üstünde `?` rozeti | Yok | Sarı | Yeni duruma kadar |
| `error` | İkonun sağ üstünde `!` rozeti | Yok | Kırmızı | Etkinlik kapanana kadar |
| `completed` | İkonun sağ üstünde `✓` rozeti | Yok | Yeşil | Mevcut 5 saniyelik otomatik kapanma boyunca |

Bir agent oturumu aynı anda yalnız bir gösterge çizer. Yeni durum geldiğinde eski gösterge
aynı slot içinde değiştirilir; ikinci agent ikonu veya ikinci kompakt slot üretilmez.

## 4. Kullanıcı Hikâyeleri

### US-001: Agent çalışmasını görmek

**Açıklama:** Kullanıcı olarak agent çalışırken küçük adadan aktif olduğunu anlamak istiyorum.

**Kabul Kriterleri:**

- [ ] `thinking`, `working` ve `usingTool` durumları aynı çalışma göstergesini kullanır.
- [ ] 3 px nokta, ikonun altında yaklaşık 8 px yatay mesafede ileri–geri gider.
- [ ] Tek yön hareketi yaklaşık 650 ms sürer ve yumuşak biçimde tersine döner.
- [ ] Hareket logo alanını, başka slotu veya adanın köşelerini kesmez.
- [ ] `idle`, `waitingForUser`, `error` ve `completed` durumlarında çalışma animasyonu yoktur.
- [ ] Swift testleri ve biçim denetimi geçer.
- [ ] Native macOS uygulamasında fiziksel/notch uyumlu ekran görüntüsüyle doğrulanır; web tarayıcı doğrulaması uygulanmaz.

### US-002: Agent sorusunu görmek

**Açıklama:** Kullanıcı olarak agent cevap beklediğinde bunu küçük adada hemen görmek istiyorum.

**Kabul Kriterleri:**

- [ ] `waitingForUser` durumunda logonun sağ üstünde sarı `?` rozeti görünür.
- [ ] Rozet logoyu tamamen kapatmaz ve slot sınırını taşırmaz.
- [ ] Çalışma noktası bu durumda durur ve kaldırılır.
- [ ] VoiceOver mevcut “Needs your input” durum metnini okumaya devam eder.
- [ ] Swift testleri ve biçim denetimi geçer.
- [ ] Native macOS uygulamasında çalışan panel üzerinden görsel doğrulama yapılır.

### US-003: Hata ve tamamlanma sonucunu görmek

**Açıklama:** Kullanıcı olarak görevin hata verdiğini veya bittiğini küçük adadan ayırt etmek istiyorum.

**Kabul Kriterleri:**

- [ ] `error` durumunda kırmızı `!` rozeti görünür.
- [ ] `completed` durumunda yeşil `✓` rozeti görünür.
- [ ] Tamamlandı rozeti `AIAgentActivity.completedAutoDismissAfter` ile aynı 5 saniye görünür.
- [ ] Görsel katman ikinci bir otomatik kapanma zamanlayıcısı oluşturmaz.
- [ ] Agent logosu bütün sonuç durumlarında görünür kalır.
- [ ] Swift testleri ve biçim denetimi geçer.
- [ ] Native macOS uygulamasında hata ve tamamlandı durumları ayrı ayrı doğrulanır.

### US-004: Erişilebilir ve senkron hareket

**Açıklama:** Kullanıcı olarak erişilebilirlik ve çoklu ekran ayarlarımda tutarlı gösterge görmek istiyorum.

**Kabul Kriterleri:**

- [ ] Hareketi Azalt açıkken çalışma noktası ikon altında sabit ve ortalanmış görünür.
- [ ] Hareketi Azalt kapalıyken animasyon yeniden çalışır.
- [ ] “Tüm ekranlar” modunda bütün adalar aynı agent durumunu gösterir.
- [ ] Ekranlar arasında soru, hata veya tamamlandı rozeti farklılaşmaz.
- [ ] Bir ekrandaki görünüm yaşam döngüsü diğer ekranda yeni activity üretmez.
- [ ] Swift testleri ve biçim denetimi geçer.
- [ ] En az iki ekranla native macOS görsel doğrulaması yapılır.

### US-005: Durum eşlemesini regresyona karşı korumak

**Açıklama:** Geliştirici olarak yedi agent durumunun yanlış göstergeye dönüşmesini önlemek istiyorum.

**Kabul Kriterleri:**

- [ ] Yedi `AIAgentState` değeri tek bir saf eşleme fonksiyonuyla göstergeye çevrilir.
- [ ] Her durum eşlemesi tablo güdümlü birim testiyle doğrulanır.
- [ ] Claude, Codex ve OpenCode aynı eşlemeyi kullanır.
- [ ] Kompakt slot yönlendirmesi agent kimliğiyle birlikte agent durumunu da korur.
- [ ] Mevcut AI erişilebilirlik metinleri değişmeden kalır.
- [ ] Tam test paketi geçer.

## 5. Fonksiyonel Gereksinimler

- **FR-1:** Sistem `AIAgentState` değerini `none`, `working`, `question`, `error` veya
  `completed` göstergesine dönüştürmelidir.
- **FR-2:** `thinking`, `working` ve `usingTool`, `working` göstergesine eşlenmelidir.
- **FR-3:** `waitingForUser`, sarı soru rozetine eşlenmelidir.
- **FR-4:** `error`, kırmızı hata rozetine eşlenmelidir.
- **FR-5:** `completed`, yeşil tamamlandı rozetine eşlenmelidir.
- **FR-6:** `idle`, hiçbir durum göstergesi çizmemelidir.
- **FR-7:** Kompakt slot agent kimliğiyle birlikte güncel agent durumunu taşımalıdır.
- **FR-8:** Agent logosu hiçbir durumda generic AI sembolüyle değiştirilmemelidir.
- **FR-9:** Bir slot aynı anda en fazla bir durum göstergesi çizmelidir.
- **FR-10:** Tamamlandı süresi mevcut 5 saniyelik activity otomatik kapanmasını kullanmalıdır.
- **FR-11:** Çalışma animasyonu yalnız çalışma göstergesi görünürken çalışmalıdır.
- **FR-12:** Hareketi Azalt açıkken zaman tabanlı hareket yerine sabit nokta çizilmelidir.
- **FR-13:** Rozetler ve çalışma noktası `CompactPillMetrics` üzerinden ölçeklenmelidir.
- **FR-14:** Yeni durum görünümü büyük AI kartına eklenmemelidir; büyük kart mevcut yazılı
  durum bilgisini korumalıdır.
- **FR-15:** Çoklu ekranlar aynı `AIAgentActivity` durumundan render edilmelidir.

## 6. Kapsam Dışı

- Büyük agent kartının yeniden tasarlanması
- Ses, bildirim veya titreşim eklenmesi
- Hook protokolü veya IPC şemasının değiştirilmesi
- Yeni agent desteği eklenmesi
- Agent durum geçiş kurallarının değiştirilmesi
- Hata metninin veya soru içeriğinin küçük adada gösterilmesi
- Kullanıcıya renk/animasyon özelleştirme ayarı eklenmesi

## 7. Tasarım Kararları

- Logo ana görsel olarak kalır; durum, küçük ikincil katmandır.
- Rozet hedef çapı 7 px, iç sembol yaklaşık 5 px olacaktır.
- Rozet sağ üst köşeye yerleşir; 22 px kompakt slot genişliğini aşmaz.
- Çalışma noktası 3 px çapında ve ikonun altında ortalanmış bir hat üzerinde hareket eder.
- Rozet renkleri sistem sarı/kırmızı/yeşil renklerinden gelir; dark yüzeyde kontrast kontrol edilir.
- Rozet değişimi kısa ölçek + opacity geçişi kullanır.
- Hareketi Azalt açıkken yalnız opacity geçişi kullanılabilir; yatay hareket kullanılmaz.

## 8. Teknik Plan

1. `AIAgentCompactIndicator` adlı `Equatable` ve `Sendable` durum tipi ekle.
2. `AIAgentState` → gösterge eşlemesini saf fonksiyonda tanımla.
3. `CompactSlot` içinde agent kimliği ve durumunu tek bir typed presentation değeriyle taşı.
4. Mevcut `AIAgentIcon` bileşenini base logo olarak bırak.
5. Yalnız kompakt görünüm için `CompactAIAgentIcon` wrapper bileşeni ekle.
6. Çalışma noktası, soru rozeti, hata rozeti ve tamamlandı rozetini wrapper içinde çiz.
7. Animasyon fazını zaman değerinden türet; çoklu ekranlar aynı zaman girdisinden benzer faz üretir.
8. Hareketi Azalt kontrolünü kompakt agent bileşeninde uygula.
9. Geometri sabitlerini `CompactPillMetrics` veya agent-specific kompakt metrics içinde tut.
10. Saf eşleme, slot yönlendirme, süre, Reduced Motion ve geometri bütçesi testlerini ekle.
11. Fiziksel notched ekran ve iki ekran düzeninde dört durumun ekran görüntüsünü doğrula.

Beklenen ana dosyalar:

- `Sources/NotchFlowUI/AIAgentActivityView.swift`
- `Sources/NotchFlowUI/CompactActivityView.swift`
- `Tests/NotchFlowUITests/AIAgentActivityViewTests.swift`
- `Tests/NotchFlowUITests/CompactActivityViewTests.swift`

IPC, hook installer ve core state-machine dosyalarında değişiklik beklenmez.

## 9. Performans ve Güvenilirlik

- Çalışan agent yokken animation timeline oluşturulmamalıdır.
- Aynı session state güncellemesi yeni slot veya yeni animation task üretmemelidir.
- Animasyon hızı görsel olarak akıcı, fakat minimum kaynak tüketimiyle sınırlandırılmalıdır.
- Slot görünümden kaldırıldığında animation task/timeline otomatik sonlanmalıdır.
- Tamamlandı için ikinci timer eklenmemeli; core activity yaşam döngüsü tek kaynak olmalıdır.
- Çoklu ekranda her panel ayrı state üretmemeli; ortak presentation kullanılmalıdır.

## 10. Başarı Ölçütleri

- Kullanıcı dört ana durumu yalnız küçük adaya bakarak ayırt edebilir.
- Yedi agent state eşleme testi eksiksiz geçer.
- Üç agent kimliği aynı gösterge davranış testlerinden geçer.
- Hareketi Azalt açıkken yatay konum değişimi sıfırdır.
- Tamamlandı göstergesi 5 saniyeden sonra activity ile birlikte kaybolur.
- Mevcut kompakt pill yüksekliği ve genişlik bütçesi aşılmaz.
- Tam Swift test paketi, App Store build ve Direct build geçer.

## 11. Açık Sorular

Yok. Kullanıcı `1A, 2A, 3A, 4A` seçeneklerini onayladı.
