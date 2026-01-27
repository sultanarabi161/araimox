import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:marquee/marquee.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

// --- CONFIGURATION ---
const String appName = "Araimox";
const String logoPath = "assets/logo.png";
// আপনার M3U লিংক এবং Notice JSON লিংক এখানে দিন
const String m3uPlaylistUrl = "https://iptv-org.github.io/iptv/index.m3u"; 
const String noticeJsonUrl = "https://raw.githubusercontent.com/your-repo/notice.json"; 

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape মোড বন্ধ করে পোর্ট্রেট ফিক্স করা হলো (স্মার্টফোনের জন্য)
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

// --- THEME & APP CONFIG ---
class AraimoxApp extends StatelessWidget {
  const AraimoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark, // স্পোর্টস অ্যাপ ডার্ক মোডে ভালো লাগে
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

// --- PROVIDER (LOGIC) ---
class AppDataProvider extends ChangeNotifier {
  List<Channel> allChannels = [];
  List<String> groups = ["All"];
  List<Channel> displayedChannels = [];
  String selectedGroup = "All";
  String noticeText = "Welcome to Araimox! Enjoy live sports.";
  bool isLoading = true;

  AppDataProvider() {
    fetchData();
  }

  Future<void> fetchData() async {
    await Future.wait([fetchM3U(), fetchNotice()]);
    isLoading = false;
    notifyListeners();
  }

  Future<void> fetchNotice() async {
    try {
      final response = await http.get(Uri.parse(noticeJsonUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        noticeText = data['notice'] ?? noticeText;
      }
    } catch (e) {
      debugPrint("Notice Error: $e");
    }
  }

  Future<void> fetchM3U() async {
    try {
      final response = await http.get(Uri.parse(m3uPlaylistUrl));
      if (response.statusCode == 200) {
        parseM3U(response.body);
      }
    } catch (e) {
      debugPrint("M3U Error: $e");
    }
  }

  void parseM3U(String content) {
    // Simple M3U Parser logic
    final lines = LineSplitter.split(content).toList();
    List<Channel> channels = [];
    Set<String> groupSet = {"All"};

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith("#EXTINF")) {
        String info = lines[i];
        String url = (i + 1 < lines.length) ? lines[i + 1] : "";
        
        // Extract Meta
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
    groups.sort(); // Sort groups alphabetically but keep 'All'
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

// --- UI: HOME PAGE ---
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppDataProvider>(context);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(logoPath, errorBuilder: (_,__,___) => const Icon(Icons.sports_soccer)),
        ),
        title: const Text(appName, style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. Notice Board (Capsule Style)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade700,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.deepPurpleAccent),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Marquee(
                        text: provider.noticeText + "      *** ",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        scrollAxis: Axis.horizontal,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        blankSpace: 20.0,
                        velocity: 50.0,
                        pauseAfterRound: const Duration(seconds: 1),
                      ),
                    ),
                  ),
                ),

                // 2. Channel Groups (Capsule Buttons)
                SizedBox(
                  height: 50,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: provider.groups.length,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemBuilder: (context, index) {
                      final group = provider.groups[index];
                      final isSelected = group == provider.selectedGroup;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(group),
                          selected: isSelected,
                          onSelected: (_) => provider.filterChannels(group),
                          shape: const StadiumBorder(),
                          selectedColor: Colors.deepPurpleAccent,
                          labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.grey),
                        ),
                      );
                    },
                  ),
                ),

                const Divider(),

                // 3. Channels Grid (4 columns)
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, // Requirement: 4 items per row
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: provider.displayedChannels.length,
                    itemBuilder: (context, index) {
                      final channel = provider.displayedChannels[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlayerPage(channel: channel),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(2,2))
                            ]
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: channel.logo.isNotEmpty
                                      ? Image.network(channel.logo, errorBuilder: (_,__,___) => const Icon(Icons.tv, size: 30))
                                      : Image.asset(logoPath, errorBuilder: (_,__,___) => const Icon(Icons.tv, size: 30)),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Text(
                                    channel.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
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

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Information"),
        content: const Text("Araimox Sports App\nVersion: 1.0.0\nDeveloped with Flutter."),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }
}

// --- UI: PLAYER PAGE ---
class PlayerPage extends StatefulWidget {
  final Channel channel;
  const PlayerPage({super.key, required this.channel});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.channel.url));
    await _videoPlayerController.initialize();
    
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: 16 / 9, // YouTube Style
      allowFullScreen: true,
      allowMuting: true,
      showControls: true, // Default Controls
      // PiP is handled by Android Platform natively, Chewie supports the UI trigger if available
      optionsTranslation: OptionsTranslation(),
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            "Stream Error: $errorMessage",
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Player Area
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const Center(child: CircularProgressIndicator()),
          ),
          
          // Metadata Area
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: widget.channel.logo.isNotEmpty 
                    ? NetworkImage(widget.channel.logo) 
                    : const AssetImage(logoPath) as ImageProvider,
                  radius: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.channel.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          borderRadius: BorderRadius.circular(4)
                        ),
                        child: Text(
                          widget.channel.group,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
