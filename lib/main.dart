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
const String appName = "Araimox";
const String logoPath = "assets/logo.png";
const String customUserAgent = "AraimoxPlayer/4.0 (Linux; Android 10) ExoPlayerLib/2.18.1";

const String configJsonUrl = "https://raw.githubusercontent.com/mxonlive/araimo/refs/heads/main/data.json"; 

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppDataProvider()),
      ],
      child: const AraimoxApp(),
    ),
  );
}

// --- THEME ---
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
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6200EA),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E1E1E),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// --- DATA MODELS ---
class Channel {
  final String name;
  final String group;
  final String logo;
  final String url;
  Channel({required this.name, required this.group, required this.logo, required this.url});
}

class AppConfig {
  String notice;
  String aboutNotice;
  String playlistUrl;
  String telegramUrl;
  bool showUpdate;
  String updateVersion;
  String updateNote;
  String downloadUrl;

  AppConfig({
    this.notice = "Welcome to Araimo!",
    this.aboutNotice = "Loading...",
    this.playlistUrl = "",
    this.telegramUrl = "",
    this.showUpdate = false,
    this.updateVersion = "",
    this.updateNote = "",
    this.downloadUrl = "",
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      notice: json['notice'] ?? "Welcome",
      aboutNotice: json['about_notice'] ?? "",
      playlistUrl: json['playlist_url'] ?? "",
      telegramUrl: json['telegram_url'] ?? "",
      showUpdate: json['update_data']?['show'] ?? false,
      updateVersion: json['update_data']?['version'] ?? "",
      updateNote: json['update_data']?['note'] ?? "",
      downloadUrl: json['update_data']?['download_url'] ?? "",
    );
  }
}

// --- PROVIDER ---
class AppDataProvider extends ChangeNotifier {
  List<Channel> allChannels = [];
  List<String> groups = ["All"];
  List<Channel> displayedChannels = [];
  String selectedGroup = "All";
  AppConfig config = AppConfig();
  bool isLoading = true;
  bool hasError = false;

  AppDataProvider() {
    initApp();
  }

  Future<void> initApp() async {
    try {
      isLoading = true;
      notifyListeners();
      
      // 1. Fetch JSON Config first
      final response = await http.get(Uri.parse(configJsonUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        config = AppConfig.fromJson(data);
        
        // 2. Fetch Playlist from JSON url
        if (config.playlistUrl.isNotEmpty) {
          await fetchM3U(config.playlistUrl);
        }
      }
    } catch (e) {
      hasError = true;
      debugPrint("Error: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchM3U(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        parseM3U(response.body);
      }
    } catch (_) {}
  }

  void parseM3U(String content) {
    final lines = LineSplitter.split(content).toList();
    List<Channel> channels = [];
    Set<String> groupSet = {"All"};

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith("#EXTINF")) {
        String info = lines[i];
        String url = (i + 1 < lines.length) ? lines[i + 1] : "";
        
        String name = info.split(',').last.trim();
        String group = "General";
        String logo = "";

        if (info.contains('group-title="')) {
          group = info.split('group-title="')[1].split('"')[0];
        }
        if (info.contains('tvg-logo="')) {
          logo = info.split('tvg-logo="')[1].split('"')[0];
        }

        if (url.startsWith("http")) {
          groupSet.add(group);
          channels.add(Channel(name: name, group: group, logo: logo, url: url));
        }
      }
    }

    allChannels = channels;
    groups = groupSet.toList();
    groups.sort();
    if(groups.contains("All")) {
      groups.remove("All");
      groups.insert(0, "All");
    }
    filterChannels("All");
  }

  void filterChannels(String group) {
    selectedGroup = group;
    if (group == "All") {
      displayedChannels = allChannels;
    } else {
      displayedChannels = allChannels.where((c) => c.group == group).toList();
    }
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
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(logoPath, errorBuilder: (_,__,___) => const Icon(Icons.play_circle_fill)),
        ),
        title: const Text(appName, style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.blueAccent),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const InfoPage()));
            },
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.hasError
            ? Center(child: ElevatedButton(onPressed: provider.initApp, child: const Text("Retry")))
            : Column(
                children: [
                  // Marquee Notice
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.deepPurple.shade900, Colors.black]),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Marquee(
                          text: provider.config.notice + "      *** ",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent),
                          velocity: 40.0,
                          blankSpace: 20.0,
                        ),
                      ),
                    ),
                  ),

                  // Group Chips
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: provider.groups.length,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemBuilder: (context, index) {
                        final group = provider.groups[index];
                        final isSelected = group == provider.selectedGroup;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(group),
                            selected: isSelected,
                            onSelected: (_) => provider.filterChannels(group),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            selectedColor: Colors.deepPurpleAccent,
                            backgroundColor: Colors.grey.shade900,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const Divider(color: Colors.white10),

                  // Channels Grid
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, 
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: provider.displayedChannels.length,
                      itemBuilder: (context, index) {
                        final channel = provider.displayedChannels[index];
                        return ChannelCard(channel: channel);
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}

class ChannelCard extends StatelessWidget {
  final Channel channel;
  const ChannelCard({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PlayerPage(channel: channel)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(2,2))]
        ),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CachedNetworkImage(
                  imageUrl: channel.logo,
                  errorWidget: (_,__,___) => Image.asset(logoPath),
                  placeholder: (_,__) => const Icon(Icons.tv, size: 20, color: Colors.grey),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))
                ),
                child: Center(
                  child: Text(
                    channel.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- INFO PAGE ---
class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  Future<void> _launchUrl(String url) async {
    if (url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not launch $url');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<AppDataProvider>(context).config;

    return Scaffold(
      appBar: AppBar(title: const Text("Information")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Logo & App Name
            Image.asset(logoPath, height: 80),
            const SizedBox(height: 10),
            const Text(appName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Version 4.0.0", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),

            // About Card
            _buildInfoCard(
              title: "About",
              content: config.aboutNotice,
              icon: Icons.info,
              color: Colors.blueAccent,
            ),

            const SizedBox(height: 15),

            // Update Card (Conditional)
            if (config.showUpdate)
              _buildInfoCard(
                title: "New Update Available!",
                content: "${config.updateVersion}\n${config.updateNote}",
                icon: Icons.system_update,
                color: Colors.green,
                actionText: "DOWNLOAD NOW",
                onTap: () => _launchUrl(config.downloadUrl),
              ),

            const SizedBox(height: 15),

            // Telegram Card
            _buildInfoCard(
              title: "Join Community",
              content: "Join our Telegram channel for latest updates and support.",
              icon: Icons.telegram,
              color: Colors.blue,
              actionText: "JOIN TELEGRAM",
              onTap: () => _launchUrl(config.telegramUrl),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(15),
        color: Colors.black,
        child: const Text(
          "Developed by Shakil Coder",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required String title, required String content, required IconData icon, required Color color, String? actionText, VoidCallback? onTap}) {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(color: Colors.white24),
            Text(content, style: const TextStyle(fontSize: 14, color: Colors.white70)),
            if (actionText != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(backgroundColor: color),
                  child: Text(actionText, style: const TextStyle(color: Colors.white)),
                ),
              )
            ]
          ],
        ),
      ),
    );
  }
}

// --- PLAYER PAGE ---
class PlayerPage extends StatefulWidget {
  final Channel channel;
  const PlayerPage({super.key, required this.channel});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool isError = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    try {
      // 1. User Agent Setup
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel.url),
        httpHeaders: {
          'User-Agent': customUserAgent, // The secret sauce for streaming
        }
      );
      await _videoPlayerController.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        aspectRatio: 16 / 9,
        allowFullScreen: true,
        showControls: true,
        errorBuilder: (context, errorMessage) {
          return Center(child: Text("Stream Error. Retry.", style: TextStyle(color: Colors.red)));
        },
      );
      setState(() {});
    } catch (e) {
      setState(() { isError = true; });
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    // Filter channels from the SAME group (Related)
    final relatedChannels = provider.allChannels
        .where((c) => c.group == widget.channel.group && c.url != widget.channel.url)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // A. Video Player Section
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child: isError 
                        ? const Center(child: Icon(Icons.error, color: Colors.red, size: 50))
                        : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                          ? Chewie(controller: _chewieController!)
                          : const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)),
                  ),
                ),
                Positioned(
                  top: 10, left: 10,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: BackButton(color: Colors.white),
                  ),
                ),
              ],
            ),

            // B. Channel Info
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF1E1E1E),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: widget.channel.logo,
                      width: 50, height: 50, fit: BoxFit.cover,
                      errorWidget: (_,__,___) => Image.asset(logoPath, width: 50),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.channel.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.deepPurple, borderRadius: BorderRadius.circular(4)),
                          child: Text(widget.channel.group, style: const TextStyle(fontSize: 11)),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),

            // C. Related Channels Title
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("More in this Group", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
            ),

            // D. Related Channels (LIST STYLE)
            Expanded(
              child: relatedChannels.isEmpty 
                ? const Center(child: Text("No more channels in this group", style: TextStyle(color: Colors.grey)))
                : ListView.builder( // Changed Grid to ListView
                    itemCount: relatedChannels.length,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemBuilder: (context, index) {
                      final related = relatedChannels[index];
                      return Card(
                        color: const Color(0xFF252525),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CachedNetworkImage(
                            imageUrl: related.logo,
                            width: 50,
                            errorWidget: (_,__,___) => const Icon(Icons.tv, color: Colors.grey),
                          ),
                          title: Text(related.name, style: const TextStyle(fontSize: 14)),
                          trailing: const Icon(Icons.play_arrow, color: Colors.deepPurpleAccent),
                          onTap: () {
                             Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => PlayerPage(channel: related)),
                            );
                          },
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
