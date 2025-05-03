import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite/tflite.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  // Ensure proper Flutter initialization
  WidgetsFlutterBinding.ensureInitialized();
  
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
  bool _loading = true; // Start with loading state so user can see something is happening
  bool _modelLoaded = false;
  File? _image;
  List? _output;
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Delay model loading slightly to allow Flutter to initialize properly
    Future.delayed(const Duration(milliseconds: 500), () {
      _initializeApp();
    });
  }
  
  // Consolidated initialization with error handling
  Future<void> _initializeApp() async {
    if (!mounted) return;
    
    try {
      // Request permissions first
      await _requestPermissions();
      
      // Then load the model
      final modelLoadResult = await _loadModel();
      
      if (modelLoadResult != null && mounted) {
        setState(() {
          _modelLoaded = true;
          _loading = false;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load model. Please restart the app.')),
          );
          setState(() {
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing: $e')),
        );
        setState(() {
          _loading = false;
        });
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

  // Load the TFLite model with explicit return value
  Future<String?> _loadModel() async {
    try {
      // First close any previously loaded model
      await Tflite.close();
      
      // Now load the model and return the result
      return await Tflite.loadModel(
        model: "assets/model.tflite",
        labels: "assets/labels.txt",
      );
    } on PlatformException catch (e) {
      debugPrint('Platform exception loading model: $e');
      return null;
    } catch (e) {
      debugPrint('General exception loading model: $e');
      return null;
    }
  }

  // Check if model is loaded and working
  Future<bool> _checkModelLoaded() async {
    try {
      if (!_modelLoaded) {
        await _reloadModel();
        return _modelLoaded;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Reload model if needed
  Future<void> _reloadModel() async {
    try {
      final result = await _loadModel();
      if (result != null && mounted) {
        setState(() {
          _modelLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error reloading model: $e');
    }
  }

  // Pick image from camera with error handling
  Future<void> _pickImageCamera() async {
    try {
      // Check model first
      final modelReady = await _checkModelLoaded();
      if (!modelReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Model not ready. Please wait or restart the app.')),
          );
        }
        return;
      }
      
      setState(() {
        _loading = true;
      });
      
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _image = File(pickedFile.path);
        });
        await _classifyImage(_image!);
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
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
      // Check model first
      final modelReady = await _checkModelLoaded();
      if (!modelReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Model not ready. Please wait or restart the app.')),
          );
        }
        return;
      }
      
      setState(() {
        _loading = true;
      });
      
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _image = File(pickedFile.path);
        });
        await _classifyImage(_image!);
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
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
        // Try reloading the model
        await _reloadModel();
        
        if (!_modelLoaded) {
          throw Exception('Model not loaded yet');
        }
      }
      
      var output = await Tflite.runModelOnImage(
        path: image.path,
        numResults: 2,
        threshold: 0.5,
        imageMean: 127.5,
        imageStd: 127.5,
      );

      if (output == null) {
        throw Exception('Classification returned null result');
      }

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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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