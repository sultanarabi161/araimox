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

// --- CONFIGURATION ---
const String appName = "araimox";
const String logoPath = "assets/logo.png";
const String m3uPlaylistUrl = "https://mxonlive.short.gy/araimo-playlist-m3u"; 

const String noticeJsonUrl = "https://raw.githubusercontent.com/sultanarabi161/araimox/refs/heads/main/notice.json"; 

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
          brightness: Brightness.dark, 
          background: Colors.black,
        ),
        scaffoldBackgroundColor: Colors.black,
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
  String noticeText = "Welcome to Araimox! Loading data...";
  bool isLoading = true;
  bool hasError = false;

  AppDataProvider() {
    fetchData();
  }

  Future<void> fetchData() async {
    isLoading = true;
    hasError = false;
    notifyListeners();

    try {
      await Future.wait([fetchM3U(), fetchNotice()]);
    } catch (e) {
      hasError = true;
      noticeText = "Error loading data. Please check internet.";
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchNotice() async {
    try {
      final response = await http.get(Uri.parse(noticeJsonUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        noticeText = data['notice'] ?? "Welcome to Araimox!";
      }
    } catch (_) {
      // Silent fail for notice
      noticeText = "Welcome to Araimox - Watch Live Sports";
    }
  }

  Future<void> fetchM3U() async {
    final response = await http.get(Uri.parse(m3uPlaylistUrl));
    if (response.statusCode == 200) {
      parseM3U(response.body);
    } else {
      throw Exception("Failed to load M3U");
    }
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
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const InfoPage()));
            },
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.hasError 
            ? Center(child: ElevatedButton(onPressed: provider.fetchData, child: const Text("Retry")))
            : Column(
              children: [
                // Notice Board
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade900,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Marquee(
                        text: provider.noticeText + "      *** ",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                        scrollAxis: Axis.horizontal,
                        velocity: 40.0,
                        blankSpace: 20.0,
                      ),
                    ),
                  ),
                ),

                // Groups
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
                          backgroundColor: Colors.grey.shade900,
                        ),
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                // Channels Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, 
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
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
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
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
                  placeholder: (_,__) => const Center(child: Icon(Icons.tv, size: 20, color: Colors.grey)),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12)
                  )
                ),
                child: Center(
                  child: Text(
                    channel.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
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

// --- UI: INFO PAGE ---
class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("App Information")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(logoPath, height: 100),
            const SizedBox(height: 20),
            const Text(appName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Version 1.0.0", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "Araimox is a smart sports streaming application designed for the best user experience. Watch your favorite channels live!",
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
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
  bool isError = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Screen won't sleep
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.channel.url));
      await _videoPlayerController.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        aspectRatio: 16 / 9,
        allowFullScreen: true,
        allowMuting: true,
        errorBuilder: (context, errorMessage) {
          return Center(child: Text("Stream Error: $errorMessage", style: const TextStyle(color: Colors.white)));
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
    // Filter related channels (Same Group)
    final relatedChannels = provider.allChannels
        .where((c) => c.group == widget.channel.group && c.url != widget.channel.url)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Player
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child: isError 
                        ? const Center(child: Text("Cannot play this stream", style: TextStyle(color: Colors.red)))
                        : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                          ? Chewie(controller: _chewieController!)
                          : const Center(child: CircularProgressIndicator()),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ],
            ),

            // 2. Info Area
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: widget.channel.logo.isNotEmpty 
                          ? NetworkImage(widget.channel.logo) 
                          : const AssetImage(logoPath) as ImageProvider,
                        fit: BoxFit.contain,
                      )
                    ),
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
                            color: Colors.deepPurple,
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

            const Divider(color: Colors.white24),

            // 3. Related Channels Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                "More from ${widget.channel.group}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),

            // 4. Related Channels List
            Expanded(
              child: relatedChannels.isEmpty 
                  ? const Center(child: Text("No other channels in this group", style: TextStyle(color: Colors.grey)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, // 3 in related list
                        childAspectRatio: 1.0,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: relatedChannels.length,
                      itemBuilder: (context, index) {
                        final related = relatedChannels[index];
                        return GestureDetector(
                          onTap: () {
                            // Replace current page with new channel
                             Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => PlayerPage(channel: related)),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: CachedNetworkImage(
                                      imageUrl: related.logo,
                                      errorWidget: (_,__,___) => const Icon(Icons.tv, color: Colors.grey),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Text(
                                    related.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                )
                              ],
                            ),
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
