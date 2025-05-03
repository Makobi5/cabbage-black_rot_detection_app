import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite/tflite.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  // Add error handling for the Flutter framework
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  
  runApp(const RotSpotApp());
}

class RotSpotApp extends StatelessWidget {
  const RotSpotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RotSpot',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = false; // Initialize as false to prevent immediate loading
  File? _image;
  List? _output;
  final picker = ImagePicker();
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    // Initialize permissions and model with proper error handling
    _initializeApp();
  }
  
  // Consolidated initialization with error handling
  Future<void> _initializeApp() async {
    try {
      await _requestPermissions();
      await _loadModel();
    } catch (e) {
      debugPrint('Initialization error: $e');
      // Show an error message to the user if needed
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing: $e')),
        );
      }
    }
  }

  // Request camera permissions
  Future<void> _requestPermissions() async {
    try {
      final statuses = await [
        Permission.camera,
        Permission.storage,
      ].request();
      
      // Check if permissions were actually granted
      if (statuses[Permission.camera] != PermissionStatus.granted ||
          statuses[Permission.storage] != PermissionStatus.granted) {
        debugPrint('Permissions not granted: $statuses');
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
      rethrow;
    }
  }

  // Load the TFLite model
  Future<void> _loadModel() async {
    try {
      await Tflite.loadModel(
        model: "assets/model.tflite",
        labels: "assets/labels.txt",
      );
      
      if (mounted) {
        setState(() {
          _modelLoaded = true;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Model loading error: $e');
      rethrow;
    }
  }

  // Pick image from camera with error handling
  Future<void> _pickImageCamera() async {
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _image = File(pickedFile.path);
          _loading = true;
        });
        await _classifyImage(_image!);
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // Pick image from gallery with error handling
  Future<void> _pickImageGallery() async {
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _image = File(pickedFile.path);
          _loading = true;
        });
        await _classifyImage(_image!);
      }
    } catch (e) {
      debugPrint('Gallery error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: $e')),
        );
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // Classify the image using the TFLite model with error handling
  Future<void> _classifyImage(File image) async {
    try {
      if (!_modelLoaded) {
        throw Exception('Model not loaded yet');
      }
      
      var output = await Tflite.runModelOnImage(
        path: image.path,
        numResults: 2,
        threshold: 0.5,
        imageMean: 127.5,
        imageStd: 127.5,
      );

      if (mounted) {
        setState(() {
          _output = output;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Classification error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Classification error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    try {
      Tflite.close();
    } catch (e) {
      debugPrint('Error closing TFLite: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RotSpot',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.green,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            color: Colors.white,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 30),
                          const Text(
                            'Detect Black Rot in Cabbage',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold, 
                              color: Colors.green,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 30),
                          Center(
                            child: _loading 
                                ? const CircularProgressIndicator()
                                : Container(
                                    constraints: BoxConstraints(
                                      maxHeight: constraints.maxHeight * 0.4,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: _image == null
                                        ? Image.asset('assets/placeholder.png')
                                        : Image.file(_image!),
                                  ),
                          ),
                          const SizedBox(height: 20),
                          if (_output != null && _output!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _output![0]['label'] == 'Healthy' ? Colors.green.shade100 : Colors.red.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Result: ${_output![0]['label']} (${(_output![0]['confidence'] * 100).toStringAsFixed(2)}%)',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _output![0]['label'] == 'Healthy' ? Colors.green.shade900 : Colors.red.shade900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickImageCamera,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickImageGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}