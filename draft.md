1. Projenin amacı

MacBook'un notch bölgesini kullanarak iPhone'daki Dynamic Island deneyimine benzer, ancak macOS için özel olarak tasarlanmış bir sistem geliştirmek.

Uygulama:

Sistem aktivitelerini gösterecek.
Uygulamalarla etkileşime girecek.
Birden fazla aktiviteyi aynı anda yönetebilecek.
Claude/Codex gibi AI uygulamalarının durumlarını gösterecek.
MacBook'un dahili ekranını otomatik algılayacak.
Çoklu monitör kullanımını doğru yönetecek.
Arka planda minimum CPU/GPU/RAM/pil tüketimi ile çalışacak.
Mac App Store üzerinden yayınlanabilecek.
Coklu dil destegimiz olucak uygulamada. 

2. Teknoloji

Native macOS uygulaması:

Swift
SwiftUI
AppKit
ActivityKit / Live Activities uygun olduğu yerlerde
Apple'ın resmi macOS API'leri
App Sandbox
Gerektiğinde uygun sistem izinleri

Üçüncü taraf framework'ler mümkün olduğunca azaltılacak.

Temel prensip:

Native macOS uygulaması, minimum bağımlılık, minimum arka plan yükü.

3. En önemli gereksinim: Performans

Bu uygulama sürekli arka planda çalışacağı için performans birinci sınıf gereksinim olacak.

Kesinlikle kaçınılacak:

Sürekli polling
while true döngüleri
Çok sık Timer kullanımı
Sürekli ekran tarama
Gereksiz Accessibility/Screen Recording kullanımı
Sürekli çalışan animasyonlar
Gereksiz network bağlantıları
Aktivite yokken UI'nin sürekli render edilmesi

Bunun yerine:

Event-driven architecture
MacOS Event
     ↓
Activity Manager
     ↓
Activity oluştur/güncelle
     ↓
Dynamic Island UI
     ↓
Aktivite bitti
     ↓
UI kapanır
     ↓
Idle

Uygulama idle durumdayken mümkün olduğunca hiçbir işlem yapmamalı.

Hedef:

CPU       → mümkün olduğunca ~0%
GPU       → idle durumda minimum
RAM       → düşük ve stabil
Wakeups   → minimum
Battery   → minimum etki

Performans testleri:

Xcode Instruments
Activity Monitor
Energy Impact
CPU profiling
Memory profiling
Wakeup/activity analizi
4. Dynamic Island UI

Notch çevresinde özel bir floating UI oluşturulacak.

Normal
              ●
Aktivite olduğunda
        ┌─────────────────┐
        │ 🎵 Music        │
        └─────────────────┘
Genişletilmiş
┌────────────────────────────────┐
│ 🎵  The Weeknd                 │
│     Blinding Lights            │
│                                │
│      ◀    ❚❚    ▶              │
└────────────────────────────────┘

Davranış:

Küçük görünüm
Geniş görünüm
Animasyonlu açılma/kapanma
Tıklama
Basılı tutma / genişletme
Aktivite bitince otomatik kapanma

Animasyonlar mümkün olduğunca düşük maliyetli olacak.

5. Ekran yönetimi

Bu özellik temel mimarinin parçası olacak.

Uygulama bağlı ekranları algılayacak:

MacBook Display
External Display 1
External Display 2

Varsayılan:

Sadece MacBook'un dahili ekranında çalış.

Örneğin:

MacBook
┌──────────────────────┐
│       NOTCHFLOW      │
│                      │
└──────────────────────┘

External Monitor
┌────────────────────────────┐
│                            │
│       hiçbir şey           │
│                            │
└────────────────────────────┘

Harici monitöre Island taşınmayacak.

Ayarlardan opsiyon
Display

● Automatic — MacBook Display
○ MacBook Display
○ External Display 1
○ External Display 2

Monitör takıldığında/çıkarıldığında uygulama otomatik tepki verecek.

Polling yerine macOS display configuration event'leri kullanılacak.

6. Activity Manager

Bütün özelliklerin merkezinde ortak bir Activity Manager bulunacak.

ActivityManager
│
├── MusicActivity
├── TimerActivity
├── CallActivity
├── ScreenRecordingActivity
├── AudioRecordingActivity
├── AirDropActivity
├── FileTransferActivity
├── ChargingActivity
│
└── AIActivity

Her activity:

start()
update()
end()

compactView()
expandedView()

priority()

mantığına sahip olacak.

Böylece ileride yeni özellik eklemek kolaylaşacak.

7. Birden fazla aktivite

Dynamic Island aynı anda birden fazla olayı yönetebilecek.

Örneğin:

🎵   ⏱   📥

Aynı anda:

Spotify
Timer
Dosya aktarımı

çalışabilir.

Genişletildiğinde:

┌──────────────────────────────┐
│ 🎵 Spotify                   │
│ ⏱ 24:32                      │
│ 📥 Download       67%        │
└──────────────────────────────┘

Activity Manager:

Öncelik
Görünürlük
Sıralama
Aktivite süresi

gibi konuları yönetecek.

8. İlk sürüm özellikleri — V1

İlk sürümde:

- Müzik
Spotify
Apple Music
Youtube Music
Diğer uygun medya kaynakları
Şarkı bilgisi
Play/pause
İleri/geri
Küçük/büyük görünüm
- Arama
Gelen arama
Devam eden arama
Arama durumu
- İlgili uygulamaya geçiş
Timer / Kronometre
Geri sayım
Kronometre
Kalan süre
- Ekran kaydı
🔴 Recording
00:24
- Sesli kayıt
🎙 Recording
00:42
- AirDrop
Aktarım başladı
İlerleme
Tamamlandı
Dosya / medya aktarımı

Önemli özelliklerden biri.

📥 Download

████████████░░░ 82%

1.2 GB / 1.5 GB

Tamamlandığında:

✓ Transfer completed

kısa süre gösterilip kapanabilir.

- Şarj

Sürekli pil yüzdesi gösterilmeyecek.

Örneğin:

MacBook şarja takıldı
        ↓
🔋 Charging
        ↓
🔋 Fully Charged
        ↓
Island kapanır
Birden fazla aktivite

Temel sistem olarak V1'de bulunacak.

9. AI entegrasyonu

Uygulamanın önemli farklılaştırıcı özelliklerinden biri.

İlk hedef:

Claude Desktop
Codex Desktop
OpenCode (Terminalden calisan sistem (Yapilip yapilmayacagini bilmiyorum eger yapilmaz ise sorun yok))

Daha sonra:

ChatGPT
Gemini
Cursor
VS Code / Copilot

Diğer AI uygulamaları
10. AI durumları

AIActivity aşağıdaki durumları destekleyecek:

Idle
 ↓
Thinking
 ↓
Working
 ↓
Using Tool
 ↓
Waiting for User
 ↓
Completed
 ↓
Error

Örneğin:

🤖 Claude
Thinking...

sonra:

🤖 Claude
Running terminal...

sonra:

✓ Claude
Task completed

veya:

⚠ Claude
Needs your input
11. AI görev tamamlanma bildirimi

Özellikle önemli.

Kullanıcı Claude/Codex'i başka bir ekranda kullanırken:

Claude
✓ Task completed

Dynamic Island'da kısa süre görünecek.

Kullanıcı tıklarsa ilgili AI uygulamasına geçilecek.

12. AI'dan kullanıcı girdisi isteme

Island genişletildiğinde:

┌──────────────────────────────┐
│ Claude                       │
│                              │
│ Needs your input             │
│                              │
│ [ Type response...       ]   │
│                              │
│              [Send]          │
└──────────────────────────────┘

İleride kullanıcı Dynamic Island üzerinden AI'a kısa bir soru gönderebilecek.

Örneğin:

"Bu hatayı düzelt."

Ancak NotchFlow kendi AI modelini çalıştırmayacak.

NotchFlow:

AI uygulamalarının kontrol/status katmanı

olarak çalışacak.

13. AI entegrasyon mimarisi
                 NotchFlow
                     │
       ┌─────────────┼─────────────┐
       ↓             ↓             ↓
    Claude          Codex       ChatGPT
       │             │             │
       └─────────────┼─────────────┘
                     ↓
              AI Activity
                     ↓
              Dynamic Island

Mümkün olduğunca:

resmi API
notification
IPC
deep link
AppleScript
uygulamanın sunduğu entegrasyonlar

kullanılacak.

Ekranı sürekli okuyarak AI'ın ne yaptığını anlamaya çalışılmayacak.

Bu hem performans hem de gizlilik açısından önemli.

14. AI izinleri

Ayarlar:

AI Integrations

Claude       ● Enabled
Codex        ● Enabled
ChatGPT      ○ Disabled

Task Started       ✓
Task Completed     ✓
Task Error         ✓
Needs Input        ✓
Tool Activity      ✓
Ask from Island    ✓

Kullanıcı hangi entegrasyonların aktif olduğunu kontrol edebilecek.

15. Öncelik sistemi

Aktivitelerin önceliği olacak:

Critical
High
Normal
Low

Örneğin:

Incoming Call
      ↓
High priority

Claude needs input
      ↓
High priority

File transfer
      ↓
Normal

Music
      ↓
Low

Böylece Island sürekli büyük hale gelmeyecek.

16. V1.5

Temel sistem stabil olduktan sonra:

Live Activities
Navigasyon
Yemek siparişi
Kargo
Canlı skor
Spor karşılaşmaları
Touch ID ile ilgili uygun sistem durumları

eklenebilir.

17. V2

Daha gelişmiş özellikler:

Akıllı ev
Daha fazla AI uygulaması
ChatGPT
Gemini
Cursor
VS Code
OpenCode
Üçüncü taraf uygulama API'si
Public API
Geliştirici SDK'sı
Kullanıcının kendi activity'lerini oluşturabilmesi

Örneğin ileride:

NotchFlow.show(...)

gibi bir geliştirici API'si düşünülebilir.

18. macOS / App Store uyumluluğu

Uygulama Mac App Store'a yayınlanacak şekilde geliştirilecek.

Başlangıçtan itibaren:

App Sandbox
Minimum entitlement
Minimum izin
Privacy açıklamaları
App Store metadata
App Store screenshot'ları
Uygulama ikonları
Privacy Policy
Apple Review Guidelines

dikkate alınacak.

"Önce uygulamayı yapalım, sonra App Store'a uydururuz" yaklaşımı kullanılmayacak.

19. İzin mimarisi

Uygulama sadece ihtiyaç duyduğu izinleri isteyecek.

Örneğin:

Screen Recording
       ↓
Gerekiyorsa kullanıcı izni

Microphone
       ↓
Gerekiyorsa kullanıcı izni

Accessibility
       ↓
Gerçekten gerekiyorsa

Files
       ↓
Sandbox / kullanıcı seçimi

Kullanıcıdan gereksiz sistem izinleri istenmeyecek.

20. Test süreci

Geliştirme:

Development
      ↓
Unit Tests
      ↓
Integration Tests
      ↓
Performance Tests
      ↓
Permission Tests
      ↓
Multi-Monitor Tests
      ↓
AI Integration Tests
      ↓
Sandbox Tests
      ↓
TestFlight
      ↓
App Store Review
      ↓
Release

Özellikle test edilecek:

MacBook tek ekran
MacBook + 1 monitör
MacBook + 2 monitör
Monitör takılması
Monitör çıkarılması
Uyku → uyanma
Lid close/open
Kullanıcı oturumu değişimi
Full-screen uygulamalar
Farklı çözünürlükler
Farklı MacBook modelleri
Dark/Light Mode
Düşük pil
Çok sayıda eşzamanlı aktivite
21. Uygulamanın çalışma prensibi

En önemli genel mimari:

                     macOS
                       │
                       ▼
               System Events
                       │
                       ▼
              ┌────────────────┐
              │ Activity Manager│
              └───────┬────────┘
                      │
          ┌───────────┼────────────┐
          ↓           ↓            ↓
        Music       Files         AI
          │           │            │
          └───────────┼────────────┘
                      ↓
               Priority Manager
                      ↓
              Dynamic Island UI
                      ↓
               MacBook Display

Ve sistem boşken:

                 IDLE
                   │
          CPU/GPU minimum
                   │
                   ↓
             macOS event
                   │
                   ↓
               ACTIVITY
                   │
                   ↓
             UI göster
                   │
                   ↓
             Activity end
                   │
                   ↓
                 IDLE

Bu yapı projenin performans temel prensibi olacak.

22. Marka ve isim

Uygulamanın resmi adı olarak Dynamic Island for MacBook kullanmak yerine bağımsız bir marka tercih edilmeli.

Şimdilik çalışma adı:

NotchFlow

Alt açıklama:

A native macOS experience for live activities, media controls, system events and AI tasks around your MacBook notch.

Apple'ın Dynamic Island ve MacBook markalarını uygulamanın kendi marka adında kullanmamak daha güvenli bir yaklaşım.

23. Geliştirme sırası

En mantıklı sıra:

1. Project Setup
       ↓
2. Performance Architecture
       ↓
3. Display Detection
       ↓
4. Notch Position / Window System
       ↓
5. Dynamic Island UI
       ↓
6. Activity Manager
       ↓
7. Music
       ↓
8. Timer
       ↓
9. Recording
       ↓
10. Calls
       ↓
11. AirDrop
       ↓
12. File Transfer
       ↓
13. Multiple Activities
       ↓
14. AI Architecture
       ↓
15. Claude
       ↓
16. Codex
       ↓
17. Settings
       ↓
18. Permissions / Sandbox
       ↓
19. Instruments Performance Testing
       ↓
20. Multi-Monitor Testing
       ↓
21. TestFlight
       ↓
22. App Store Submission

Temel kural: Önce sağlam Core + Display + Activity Manager + performans altyapısı, sonra özellikler.

Bu şekilde proje büyüdükçe sistemi yeniden yazmak yerine yeni Activity modülleri ekleyerek ilerleyebiliriz.