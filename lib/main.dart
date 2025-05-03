import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

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
  Map<String, double>? _output;
  final picker = ImagePicker();
  
  // Custom model variables
  late ImageLabeler _imageLabeler;
  List<String> _labels = [];
  bool _isModelDownloaded = false;

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
      
      if (modelLoadResult && mounted) {
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

  // Load the model with explicit return value
  Future<bool> _loadModel() async {
    try {
      // Load labels
      final labelsData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelsData.trim().split('\n');
      
      // Copy model file to device storage from assets
      final modelPath = await _getModelPath('assets/model.tflite');
      
      // Create custom image labeler
      final options = LocalLabelerOptions(
        confidenceThreshold: 0.5,
        modelPath: modelPath,
      );
      
      _imageLabeler = ImageLabeler(options: options);
      _isModelDownloaded = true;
      
      return true;
    } catch (e) {
      debugPrint('General exception loading model: $e');
      return false;
    }
  }
  
  // Helper to get model file path from assets
  Future<String> _getModelPath(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/black_rot_model.tflite');
    await file.writeAsBytes(byteData.buffer.asUint8List(
        byteData.offsetInBytes, byteData.lengthInBytes));
    return file.path;
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
      if (result && mounted) {
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

  // Convert File to InputImage for ML Kit
  InputImage _getInputImage(File imageFile) {
    return InputImage.fromFilePath(imageFile.path);
  }

  // Classify the image using the model
  Future<void> _classifyImage(File image) async {
    try {
      if (!_modelLoaded) {
        // Try reloading the model
        await _reloadModel();
        
        if (!_modelLoaded) {
          throw Exception('Model not loaded yet');
        }
      }
      
      // Convert to InputImage
      final inputImage = _getInputImage(image);
      
      // Process the image with ML Kit
      final List<ImageLabel> labels = await _imageLabeler.processImage(inputImage);
      
      // Check results
      if (labels.isEmpty) {
        throw Exception('No labels detected');
      }
      
      // Create output map with label and confidence
      final result = <String, double>{};
      
      // Get the highest confidence label
      final highestConfidenceLabel = labels.reduce(
        (curr, next) => curr.confidence > next.confidence ? curr : next
      );
      
      // Map the detected label to our application's labels if possible
      // Most ML Kit models return generic labels, but your model might have specific classes
      String labelText = highestConfidenceLabel.label;
      
      // If your model uses indices instead of text labels
      // You may need to map the index to your label list
      if (int.tryParse(labelText) != null) {
        final index = int.parse(labelText);
        if (index < _labels.length) {
          labelText = _labels[index];
        }
      }
      
      result[labelText] = highestConfidenceLabel.confidence;

      if (mounted) {
        setState(() {
          _output = result;
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
    _imageLabeler.close();
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
                              color: _output!.keys.first == 'Healthy' ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Result: ${_output!.keys.first} (${(_output!.values.first * 100).toStringAsFixed(2)}%)',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _output!.keys.first == 'Healthy' ? Colors.green.shade900 : Colors.red.shade900,
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