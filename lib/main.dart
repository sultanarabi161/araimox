import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:marquee/marquee.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

// --- CONFIGURATION ---
const String appName = "araimox";
const String logoPath = "assets/logo.png";
const String customUserAgent = "AraimoxPlayer/5.0 (Linux; Android 10) ExoPlayerLib/2.18.1";
const String configJsonUrl = "https://raw.githubusercontent.com/mxonlive/araimo/refs/heads/main/data.json"; 

// --- PREMIUM COLORS ---
const Color kRed = Color(0xFFE50914);       // Brand Red
const Color kBlack = Color(0xFF000000);     // Pure Black
const Color kDarkGrey = Color(0xFF141414);  // Surface
const Color kLightGrey = Color(0xFFB3B3B3); // Secondary Text

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppDataProvider())],
      child: const AraimoxApp(),
    ),
  );
}

class AraimoxApp extends StatelessWidget {
  const AraimoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBlack,
        primaryColor: kRed,
        colorScheme: const ColorScheme.dark(
          primary: kRed,
          surface: kDarkGrey,
          background: kBlack,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// --- DATA PROVIDER ---
class AppDataProvider extends ChangeNotifier {
  List<dynamic> allChannels = [];
  List<String> groups = ["All"];
  List<dynamic> displayedChannels = [];
  String selectedGroup = "All";
  Map<String, dynamic> config = {
    "notice": "Welcome to Araimox",
    "playlist_url": "",
    "about_notice": "",
    "telegram_url": "",
    "show_update": false
  };
  bool isLoading = true;

  AppDataProvider() {
    initApp();
  }

  Future<void> initApp() async {
    isLoading = true;
    notifyListeners();
    try {
      final res = await http.get(Uri.parse(configJsonUrl));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        config = {
          "notice": data['notice'] ?? "Welcome",
          "playlist_url": data['playlist_url'] ?? "",
          "about_notice": data['about_notice'] ?? "",
          "telegram_url": data['telegram_url'] ?? "",
          "show_update": data['update_data']?['show'] ?? false,
          "update_ver": data['update_data']?['version'] ?? "",
          "update_note": data['update_data']?['note'] ?? "",
          "dl_url": data['update_data']?['download_url'] ?? "",
        };
        if (config['playlist_url'].isNotEmpty) {
          await fetchM3U(config['playlist_url']);
        }
      }
    } catch (_) {}
    isLoading = false;
    notifyListeners();
  }

  Future<void> fetchM3U(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) parseM3U(res.body);
    } catch (_) {}
  }

  void parseM3U(String content) {
    final lines = LineSplitter.split(content).toList();
    List<dynamic> channels = [];
    Set<String> groupSet = {"All"};

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith("#EXTINF")) {
        String info = lines[i];
        String url = (i + 1 < lines.length) ? lines[i + 1] : "";
        String name = info.split(',').last.trim();
        String group = info.contains('group-title="') ? info.split('group-title="')[1].split('"')[0] : "General";
        String logo = info.contains('tvg-logo="') ? info.split('tvg-logo="')[1].split('"')[0] : "";
        
        if (url.startsWith("http")) {
          groupSet.add(group);
          channels.add({"name": name, "group": group, "logo": logo, "url": url});
        }
      }
    }
    allChannels = channels;
    groups = groupSet.toList()..sort();
    if(groups.contains("All")) { groups.remove("All"); groups.insert(0, "All"); }
    filterChannels("All");
  }

  void filterChannels(String group) {
    selectedGroup = group;
    displayedChannels = group == "All" ? allChannels : allChannels.where((c) => c['group'] == group).toList();
    notifyListeners();
  }
}

// --- HOME PAGE ---
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppDataProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kBlack.withOpacity(0.9), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        leading: Padding(padding: const EdgeInsets.all(12), child: Image.asset(logoPath)),
        title: Text(appName, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3, color: kRed, fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoPage()))),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : Column(
              children: [
                const SizedBox(height: 100), // Space for AppBar
                // Notice
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  height: 40,
                  decoration: BoxDecoration(
                    color: kRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kRed.withOpacity(0.3))
                  ),
                  child: Marquee(
                    text: provider.config['notice'] + "     ★     ",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    velocity: 30,
                  ),
                ),
                
                // Group Filter
                Container(
                  height: 60,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: provider.groups.length,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemBuilder: (context, index) {
                      final group = provider.groups[index];
                      final isSelected = group == provider.selectedGroup;
                      return GestureDetector(
                        onTap: () => provider.filterChannels(group),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? kRed : kDarkGrey,
                            borderRadius: BorderRadius.circular(20),
                            border: isSelected ? null : Border.all(color: Colors.white12),
                          ),
                          child: Text(group.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Colors.white : kLightGrey)),
                        ),
                      );
                    },
                  ),
                ),

                // Channels Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, // Slightly bigger cards
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: provider.displayedChannels.length,
                    itemBuilder: (context, index) {
                      final channel = provider.displayedChannels[index];
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(channel: channel))),
                        child: Container(
                          decoration: BoxDecoration(
                            color: kDarkGrey,
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: NetworkImage(channel['logo']),
                              fit: BoxFit.cover, // FULL ZOOM (No empty space)
                            ),
                            boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 5)]
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.6, 1.0]
                              ),
                            ),
                            alignment: Alignment.bottomCenter,
                            padding: const EdgeInsets.all(5),
                            child: Text(
                              channel['name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// --- PLAYER PAGE (IMPROVED UI) ---
class PlayerPage extends StatefulWidget {
  final Map<String, dynamic> channel;
  const PlayerPage({super.key, required this.channel});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _vc;
  ChewieController? _cc;
  bool isError = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    initPlayer();
  }

  Future<void> initPlayer() async {
    try {
      _vc = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel['url']),
        httpHeaders: {'User-Agent': customUserAgent}
      );
      await _vc.initialize();
      _cc = ChewieController(
        videoPlayerController: _vc,
        autoPlay: true,
        aspectRatio: 16 / 9,
        allowFullScreen: true,
        showControls: true,
      );
      setState(() {});
    } catch (e) {
      setState(() { isError = true; });
    }
  }

  @override
  void dispose() {
    _vc.dispose();
    _cc?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final related = provider.allChannels
        .where((c) => c['group'] == widget.channel['group'] && c['url'] != widget.channel['url'])
        .toList();

    return Scaffold(
      backgroundColor: kBlack,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. VIDEO PLAYER
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child: isError 
                      ? const Center(child: Icon(Icons.error, color: kRed)) 
                      : (_cc != null ? Chewie(controller: _cc!) : const Center(child: CircularProgressIndicator(color: kRed))),
                  ),
                ),
                // NEW BACK BUTTON
                Positioned(
                  top: 15, left: 15,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24)
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),

            // 2. INFO
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.channel['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(4)),
                    child: Text(widget.channel['group'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10),

            // 3. RELATED CHANNELS (Horizontal Scroll - Netflix Style)
            if (related.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: Text("MORE LIKE THIS", style: TextStyle(color: kLightGrey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
              SizedBox(
                height: 140, // Height for horizontal cards
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: related.length,
                  itemBuilder: (context, index) {
                    final item = related[index];
                    return GestureDetector(
                      onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlayerPage(channel: item))),
                      child: Container(
                        width: 160,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: kDarkGrey,
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: NetworkImage(item['logo']),
                            fit: BoxFit.cover,
                            opacity: 0.7
                          ),
                          border: Border.all(color: Colors.white10)
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          child: Icon(Icons.play_circle_outline, color: Colors.white.withOpacity(0.8), size: 40),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// --- INFO PAGE ---
class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<AppDataProvider>(context).config;
    return Scaffold(
      appBar: AppBar(title: const Text("APP INFO")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Image.asset(logoPath, height: 100)),
          const SizedBox(height: 20),
          const Center(child: Text(appName, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kRed, letterSpacing: 2))),
          const SizedBox(height: 40),
          
          _tile("About", config['about_notice'], Icons.info_outline, Colors.blue),
          if (config['show_update'])
            _tile("Update Available", config['update_note'], Icons.system_update, Colors.green, url: config['dl_url']),
          _tile("Telegram Community", "Join us for support", Icons.telegram, Colors.blueAccent, url: config['telegram_url']),
          
          const SizedBox(height: 50),
          const Center(child: Text("Version 5.0.0 • Build by sultanarabi161", style: TextStyle(color: Colors.grey, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _tile(String title, String sub, IconData icon, Color color, {String? url}) {
    return Card(
      color: kDarkGrey,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: url != null && url.isNotEmpty ? () => launchUrl(Uri.parse(url)) : null,
      ),
    );
  }
}
