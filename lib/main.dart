import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(ChatApp());
}

class ChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.purple[800]!,
        ),
      ),
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  String assistantMessage = '';
  List<String> chatHistory = [];
  late FlutterTts flutterTts;
  final stt.SpeechToText speech = stt.SpeechToText();
  final stt.SpeechToText recorderSpeech = stt.SpeechToText(); // Recorder's speech to text

  bool isMicOn = false;
  bool isListening = false;
  bool isRecording = false;

  String recorderText = ''; // Variable to store recorder's text

  @override
  void initState() {
    super.initState();
    _initializeTextToSpeech();
    _loadChatHistory(); // Load chat history from SharedPreferences
  }

  void _initializeTextToSpeech() {
    flutterTts = FlutterTts()
      ..setLanguage('en-US')
      ..setVoice({"name": "en-US-x-sfg#female_1-local", "locale": "en-US"})
      ..setPitch(1.0)
      ..setSpeechRate(0.5)
      ..setCompletionHandler(() {
        _startListening();
      });
  }

  void _speakAssistantMessage() async {
    if (assistantMessage.isNotEmpty) {
      await flutterTts.speak(assistantMessage);
    } else {
      _startListening();
    }
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      chatHistory = prefs.getStringList('chatHistory') ?? [];
      _addWelcomeMessage();
    });
  }

  void _addWelcomeMessage() =>
      _assistantResponse("Hey Ova lets start a quick conversation.");

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('chatHistory', chatHistory);
  }

  void _toggleMic() {
    if (isListening) {
      _turnOffMic();
    } else {
      _startListening();
    }
  }

  void _startListening() async {
    if (await speech.initialize()) {
      speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            _handleSpeechResult(result.recognizedWords);
          }
        },
      );
      setState(() {
        isMicOn = true;
        isListening = true;
      });
    } else {
      print('Speech recognition not available');
    }
  }

  // Function to start recorder's speech to text
  void _startRecording() async {
    if (await recorderSpeech.initialize()) {
      recorderSpeech.listen(
        onResult: (result) {
          if (result.finalResult) {
            setState(() {
              recorderText = result.recognizedWords;
            });
            // Automatically add recorded text to shared preferences
            if (recorderText.isNotEmpty) {
              chatHistory.add('User (Recorder): $recorderText');
              _saveChatHistory();
              recorderText = ''; // Make recorderText empty
            }
          }
        },
      );
      setState(() {
        isRecording = true;
      });
    } else {
      print('Recorder speech recognition not available');
    }
  }

  // Function to stop recording
  void _stopRecording() {
    recorderSpeech.stop();
    setState(() {
      isRecording = false;
    });
  }

  void _handleSpeechResult(String text) {
    if (text.isNotEmpty) {
      _textController.text = text;
      if (text.toLowerCase() == "start") {
        _textController.clear();
        _handleSubmitted();
      } else if (text.toLowerCase() == "bye" || text.toLowerCase() == "goodbye") {
        _turnOffMic();
        _assistantResponse(text);
      } else {
        _handleSubmitted();
      }
    }
  }

  void _assistantResponse(String userMessage) async {
    chatHistory.add('User: $userMessage');
    final apiKey = "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";
    final apiUrl = "https://api.openai.com/v1/chat/completions";

    final conversationContext = chatHistory.join('\n'); // Combine chat history as context

    final response = await sendMessage(apiUrl, apiKey, conversationContext);

    if (response != null) {
      assistantMessage = response['choices'][0]['message']['content'];
      assistantMessage = assistantMessage.replaceAll("OVA:", "");
      chatHistory.add(assistantMessage);
      _messages.add(ChatMessage(text: assistantMessage, isUser: false));
      _speakAssistantMessage();

      if (assistantMessage.toLowerCase().contains("bye") || assistantMessage.toLowerCase().contains("goodbye")) {
        _turnOffMic();
      }

      _saveChatHistory();
      setState(() {});
    }
  }

  Future<Map<String, dynamic>?> sendMessage(
      String apiUrl, String apiKey, String conversationContext) async {
    final messageList = [
      {
        "role": "system",
        "content":
        "Hey, I am giving you a role to behave for future responses. Your Name is OVA (Online Virtual Assistant), and You are a virtual Assistant. You have to give a response similar to human Conversation as text output. Use greetings in the response."
      },
      {"role": "user", "content": conversationContext},
    ];

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {"Authorization": "Bearer $apiKey", "Content-Type": "application/json"},
      body: json.encode({"model": "gpt-3.5-turbo", "messages": messageList}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      print("Error: Failed to get a response from GPT API");
      return null;
    }
  }

  final TextEditingController _textController = TextEditingController();

  void _handleSubmitted() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _messages.add(ChatMessage(text: text, isUser: true));
      chatHistory.add('User: $text');
      _assistantResponse(text);
      _textController.clear();
      _saveChatHistory();
    }
  }

  void _turnOffMic() {
    speech.stop();
    setState(() {
      isMicOn = false;
      isListening = false;
    });
  }

  void _showChatHistoryDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Chat History"),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: chatHistory.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(chatHistory[index]),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Close"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('OVA DRIVE'),
        actions: [
          // Recorder button in app bar
          IconButton(
            icon: Icon(isRecording ? Icons.mic : Icons.mic_off),
            onPressed: () {
              setState(() {
                if (isRecording) {
                  _stopRecording();
                } else {
                  _startRecording();
                }
              });
            },
          ),
          // View Chat History button in app bar
          IconButton(
            icon: Icon(Icons.history),
            onPressed: _showChatHistoryDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) => _messages.reversed.toList()[index],
            ),
          ),
          Divider(height: 1.0),
          ChatInput(
            handleSubmitted: _handleSubmitted,
            toggleMic: _toggleMic,
            isMicOn: isMicOn,
            isListening: isListening,
            textController: _textController,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    flutterTts.stop();
    speech.stop();
    recorderSpeech.stop(); // Stop recorder's speech to text when disposing
    super.dispose();
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 0.85 * MediaQuery.of(context).size.width,
        padding: EdgeInsets.all(8.0),
        child: Container(
          padding: EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isUser ? [Colors.blue[900]!, Colors.purple[900]!] : [Colors.purple[900]!, Colors.purple[600]!],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16.0),
              topRight: Radius.circular(16.0),
              bottomLeft: isUser ? Radius.circular(16.0) : Radius.zero,
              bottomRight: isUser ? Radius.zero : Radius.circular(16.0),
            ),
          ),
          child: Text(text, style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class ChatInput extends StatefulWidget {
  final Function() handleSubmitted;
  final Function() toggleMic;
  final bool isMicOn;
  final bool isListening;
  final TextEditingController textController;

  ChatInput({
    required this.handleSubmitted,
    required this.toggleMic,
    required this.isMicOn,
    required this.isListening,
    required this.textController,
  });

  @override
  _ChatInputState createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(9.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(widget.isMicOn ? Icons.mic : Icons.mic_off),
            onPressed: widget.toggleMic,
          ),
          Expanded(
            child: TextField(
              controller: widget.textController,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.isListening
                    ? 'Listening...'
                    : 'Type a message...',
                hintStyle: TextStyle(
                  color: widget.isListening ? Colors.purple[150] : Colors.grey[400],
                ),
              ),
              onSubmitted: (_) => widget.handleSubmitted(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: widget.handleSubmitted,
          ),
        ],
      ),
    );
  }
}
