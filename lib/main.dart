import 'dart:io';
import 'dart:typed_data'; // Required for Float32List and Uint8List
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img; // Prefixing to avoid conflicts
import 'package:tflite_flutter/tflite_flutter.dart'; // Import the tflite_flutter package


void main() {
  // Ensure proper Flutter initialization
  WidgetsFlutterBinding.ensureInitialized();

  // Add error handling for the Flutter framework
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // You might want to log these errors to a service in production
    debugPrint("FlutterError: ${details.exceptionAsString()} \n ${details.stack}");
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
        useMaterial3: true, // Optional: Use Material 3 design
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
  bool _loading = true; // Show loading initially while model loads
  bool _modelLoaded = false;
  File? _image;
  Map<String, double>? _output; // Stores label and confidence
  final picker = ImagePicker();

  // TFLite specific variables
  Interpreter? _interpreter;
  List<String> _labels = [];

  // --- IMPORTANT: Adjust these values based on your specific model ---
  // Common input size for many image models
  final int _inputWidth = 224;
  final int _inputHeight = 224;
  // Normalization parameters (example for scaling 0-255 pixels to 0.0-1.0 float range)
  // If your model expects [-1, 1], use mean: 127.5, std: 127.5
  final double _normalizationMean = 0.0;
  final double _normalizationStd = 255.0;
  // Ensure your model input type is Float32 if using these values
  // --- End of model specific values ---


  @override
  void initState() {
    super.initState();
    // Delay slightly to ensure rendering before heavy work
    Future.delayed(const Duration(milliseconds: 300), _initializeApp);
  }

  @override
  void dispose() {
    // Release TFLite resources
    _interpreter?.close();
    debugPrint("TFLite Interpreter closed.");
    super.dispose();
  }

  // Consolidated initialization
  Future<void> _initializeApp() async {
    if (!mounted) return;

    try {
      await _requestPermissions();
      final modelLoadResult = await _loadModel();

      if (modelLoadResult && mounted) {
        setState(() {
          _modelLoaded = true;
          _loading = false; // Stop initial loading indicator
        });
        debugPrint("Model loaded successfully.");
      } else {
        // Keep loading true if model failed, show error
        if (mounted) {
          _showErrorSnackbar('Failed to load model. Please restart the app.');
          setState(() { _loading = false; }); // Or keep loading indicator? User decision.
        }
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        _showErrorSnackbar('Error during initialization: $e');
        setState(() { _loading = false; });
      }
    }
  }

  // Request necessary permissions
  Future<void> _requestPermissions() async {
    try {
      final statuses = await [
        Permission.camera,
        // Storage permission might not be strictly needed on newer Android/iOS
        // for ImagePicker, but can be good practice depending on other operations.
        // Permission.storage,
      ].request();

      if (statuses[Permission.camera] != PermissionStatus.granted) {
        debugPrint('Camera permission not granted.');
        _showErrorSnackbar('Camera permission is required to take photos.');
        // Optionally, guide user to settings using `openAppSettings()`
      }
      // Check other permissions if requested
    } catch (e) {
      debugPrint('Permission request error: $e');
      _showErrorSnackbar('Error requesting permissions: $e');
      rethrow; // Rethrow to be caught by _initializeApp if needed
    }
  }

  // Load TFLite model and labels
  Future<bool> _loadModel() async {
    try {
      // Load labels from assets
      final labelsData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelsData.trim().split('\n');
      if (_labels.isEmpty) {
        debugPrint("Error: labels.txt is empty or not found.");
        return false;
      }
      debugPrint("Labels loaded: ${_labels.length} labels.");

      // Create TFLite interpreter from asset
      // Optionally configure InterpreterOptions (e.g., for GPU Delegate or NNAPI)
      // final options = InterpreterOptions()..addDelegate(GpuDelegateV2());
      _interpreter = await Interpreter.fromAsset(
          'assets/model.tflite',
          // options: options // Uncomment to use options
          );

      // Verify input/output tensor details (useful for debugging)
      var inputTensor = _interpreter!.getInputTensor(0);
      var outputTensor = _interpreter!.getOutputTensor(0);
      debugPrint("Model Input Shape: ${inputTensor.shape}, Type: ${inputTensor.type}");
      debugPrint("Model Output Shape: ${outputTensor.shape}, Type: ${outputTensor.type}");

      // Basic validation (Adjust based on your model's specifics)
      bool inputShapeOk = inputTensor.shape.length == 4 &&
                          inputTensor.shape[1] == _inputHeight &&
                          inputTensor.shape[2] == _inputWidth &&
                          inputTensor.shape[3] == 3; // Assuming RGB
     bool inputTypeOK = inputTensor.type == TfLiteType.kTfLiteFloat32;// Check if matches your normalization
      bool outputShapeOk = outputTensor.shape.length == 2 &&
                           outputTensor.shape[1] == _labels.length; // Output neurons match labels

      if (!inputShapeOk) debugPrint("Warning: Input shape mismatch. Expected [1, $_inputHeight, $_inputWidth, 3], Got ${inputTensor.shape}");
      if (!inputTypeOK) debugPrint("Warning: Input type mismatch. Expected Float32 for chosen normalization, Got ${inputTensor.type}");
// ...
return inputTypeOK && outputShapeOk; // Return true if basic checks pass
      if (!outputShapeOk) debugPrint("Warning: Output shape mismatch. Expected [1, ${_labels.length}], Got ${outputTensor.shape}");


      // Consider inputTypeOk and outputShapeOk for returning false if critical
      return inputTypeOK && outputShapeOk; // Return true if basic checks pass

    } catch (e) {
      debugPrint('Error loading TFLite model: $e');
      _interpreter?.close(); // Clean up if loading failed
      _interpreter = null;
      return false;
    }
  }

  // Check if the model is loaded and ready
  bool _checkModelReady() {
      if (_interpreter == null || !_modelLoaded) {
        _showErrorSnackbar('Model is not ready. Please wait or restart the app.');
        return false;
      }
      return true;
  }

  // Unified function to pick image and start classification
  Future<void> _pickAndProcessImage(ImageSource source) async {
    if (!_checkModelReady() || _loading) return; // Prevent action if model not ready or already processing

    try {
      setState(() {
        _loading = true; // Show processing indicator
        _output = null; // Clear previous results
        // Keep _image visible while processing new one if desired
      });

      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 85, // Adjust quality as needed
        // You might want to set maxWidth/maxHeight here, but preprocessing will resize anyway
        // maxWidth: 1000,
        // maxHeight: 1000,
      );

      if (pickedFile != null && mounted) {
        final imageFile = File(pickedFile.path);
        // Update the displayed image immediately
        setState(() {
          _image = imageFile;
        });
        // Start classification
        await _classifyImage(imageFile);
      } else {
        // User cancelled picker or something went wrong
        if (mounted) {
          setState(() { _loading = false; }); // Hide processing indicator
        }
      }
    } catch (e) {
      debugPrint('Image picking/processing error ($source): $e');
      if (mounted) {
        _showErrorSnackbar('Error selecting or processing image: $e');
        setState(() { _loading = false; _image = null; }); // Clear image on error?
      }
    }
  }

  // --- Image Preprocessing ---
  Future<Uint8List> _preprocessImage(File imageFile) async {
    try {
      // 1. Read image bytes from file
      final bytes = await imageFile.readAsBytes();

      // 2. Decode image using 'image' package
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('Failed to decode image.');
      }

      // 3. Resize the image to the model's expected input size
      img.Image resizedImage = img.copyResize(
        originalImage,
        width: _inputWidth,
        height: _inputHeight,
        interpolation: img.Interpolation.linear, // Or bilinear, nearest etc.
      );

      // 4. Convert to Float32List and Normalize pixel values
      // Model expects shape [1, height, width, 3] (batch, height, width, channels)
      // The Float32List will store the pixel data sequentially.
      var inputBytes = Float32List(1 * _inputHeight * _inputWidth * 3);
      int pixelIndex = 0;
      for (int y = 0; y < _inputHeight; y++) {
        for (int x = 0; x < _inputWidth; x++) {
          var pixel = resizedImage.getPixel(x, y);
          // Normalize RGB values based on defined mean and std deviation
          inputBytes[pixelIndex++] = (pixel.r - _normalizationMean) / _normalizationStd;
          inputBytes[pixelIndex++] = (pixel.g - _normalizationMean) / _normalizationStd;
          inputBytes[pixelIndex++] = (pixel.b - _normalizationMean) / _normalizationStd;
        }
      }
      // Return the byte buffer of the Float32List
      return inputBytes.buffer.asUint8List();

    } catch (e) {
        debugPrint('Image preprocessing failed: $e');
        throw Exception('Failed to preprocess image: $e'); // Rethrow to be caught by caller
    }
  }

  // --- Image Classification using TFLite ---
  Future<void> _classifyImage(File image) async {
    if (_interpreter == null) {
       _showErrorSnackbar('Interpreter not initialized.');
       setState(() { _loading = false; });
       return;
    }

    try {
      // 1. Preprocess the image: resize and normalize
      final inputBytes = await _preprocessImage(image);

      // 2. Prepare input tensor for the interpreter
      // Needs to match the input shape: [1, H, W, C]
      // The `inputBytes` are already in the correct flat format for a Float32 input.
      // We need to wrap it in a list structure if the run method expects it,
      // but often passing the buffer directly works for single input models.
      // Let's create the input list structure explicitly for clarity:
      // Reshape the flat buffer into the expected shape [1, 224, 224, 3]
      // This reshape might be handled internally by some versions/APIs,
      // but creating the structure explicitly is safer.
      // However, tflite_flutter often takes the flat buffer directly if shape matches.
      // Let's use the direct buffer approach first.
      var inputs = [inputBytes]; // Wrap the preprocessed bytes in a list


      // 3. Prepare output tensor buffer
      // Shape is usually [1, num_classes], Type Float32
      var outputTensor = _interpreter!.getOutputTensor(0);
      var outputShape = outputTensor.shape; // e.g., [1, 5] for 5 classes
      var outputType = outputTensor.type;   // e.g., TfLiteType.float32
      int numClasses = outputShape[1];

      // Create a buffer to store the output
      // For Float32 output, create a List<List<double>>
      dynamic outputs;
      if (outputType == TfLiteType.kTfLiteFloat32) {
  outputs = List.generate(outputShape[0], (_) => List<double>.filled(numClasses, 0.0));
} else if (outputType == TfLiteType.kTfLiteUInt8) {
  outputs = List.generate(outputShape[0], (_) => List<int>.filled(numClasses, 0));
}
      else {
           _showErrorSnackbar("Unsupported model output type: $outputType");
           setState(() { _loading = false; });
           return;
      }

      // 4. Run inference
      debugPrint("Running inference...");
      // Pass the input buffer and the pre-allocated output buffer
      _interpreter!.run(inputs[0], outputs);
      debugPrint("Inference complete.");

      // 5. Process the output
      // `outputs` now holds the model's predictions, e.g., [[0.1, 0.05, 0.7, 0.15]]
      List<dynamic> scores = outputs[0]; // Get the inner list of scores/values

      // Find the index with the highest score
      double maxScore = 0.0;
      int maxIndex = -1;
      for (int i = 0; i < scores.length; i++) {
        double currentScore;
        // Handle different output types if necessary
        if (outputType == TfLiteType.kTfLiteFloat32) {
            currentScore = scores[i];
        } else if (outputType == TfLiteType.kTfLiteUInt8) {
            // Basic conversion assuming 0-255 maps to 0.0-1.0 probability
            currentScore = scores[i] / 255.0;
            // For quantized models, proper dequantization might be needed:
            // scale * (value - zero_point)
        } else {
             currentScore = 0.0; // Should have been caught earlier
        }

        if (currentScore > maxScore) {
          maxScore = currentScore;
          maxIndex = i;
        }
      }

      final result = <String, double>{};
      if (maxIndex != -1 && maxIndex < _labels.length) {
        // Map the index to the corresponding label
        result[_labels[maxIndex]] = maxScore;
        debugPrint("Classification Result: Label=${_labels[maxIndex]}, Confidence=$maxScore");
      } else {
          debugPrint("Failed to find highest score index or index out of bounds.");
          result["Unknown"] = 0.0; // Indicate failure or unknown result
      }

      if (mounted) {
        setState(() {
          _output = result;
          _loading = false; // Classification finished
        });
      }

    } catch (e) {
      debugPrint('Classification error: $e');
      if (mounted) {
        _showErrorSnackbar('Error during classification: $e');
        setState(() {
          _loading = false; // Stop loading on error
          _output = null; // Clear results on error
        });
      }
    }
  }

  // Helper to show Snackbars
  void _showErrorSnackbar(String message) {
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
                 content: Text(message),
                 backgroundColor: Colors.redAccent,
                 duration: const Duration(seconds: 3),
             )
          );
      }
  }

  // --- Build Method ---
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
        elevation: 2,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            color: Colors.white,
            child: Column(
              children: [
                // Content Area (Image and Result)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Detect Black Rot in Cabbage',
                          style: TextStyle(
                            fontSize: 22, // Slightly smaller
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 25),

                        // Image display area
                        Center(
                          child: Container(
                            constraints: BoxConstraints(
                              // Max height relative to available space minus buttons/padding
                              maxHeight: constraints.maxHeight * 0.45,
                              maxWidth: constraints.maxWidth * 0.8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300, width: 1.5)
                            ),
                            child: ClipRRect( // Clip image to rounded corners
                               borderRadius: BorderRadius.circular(11), // Slightly smaller than border
                               child: Stack( // Stack for loading indicator over image
                                alignment: Alignment.center,
                                children: [
                                  // Show initial loading, placeholder, or the image
                                  if (_loading && _image == null)
                                    const Column(
                                       mainAxisAlignment: MainAxisAlignment.center,
                                       children: [
                                         CircularProgressIndicator(),
                                         SizedBox(height: 15),
                                         Text("Loading Model...", style: TextStyle(color: Colors.grey))
                                       ],
                                     )
                                  else if (_image == null)
                                    Image.asset(
                                      'assets/placeholder.png',
                                       fit: BoxFit.contain, // Was contain before
                                       height: constraints.maxHeight * 0.4, // Give placeholder size
                                    )
                                  else
                                    Image.file(
                                      _image!,
                                      fit: BoxFit.cover, // Cover might look better if aspect ratios differ
                                      width: double.infinity, // Fill container width
                                      height: double.infinity, // Fill container height
                                    ),

                                  // Show processing indicator over the image
                                  if (_loading && _image != null)
                                    Container(
                                      color: Colors.black.withOpacity(0.3),
                                      child: const Center(child: CircularProgressIndicator( valueColor: AlwaysStoppedAnimation<Color>(Colors.white),))
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),

                        // Results display area
                        // Animate the appearance of the result container
                        AnimatedOpacity(
                          opacity: (_output != null && _output!.isNotEmpty && !_loading) ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 500),
                          child: _output != null && _output!.isNotEmpty
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _output!.keys.first.toLowerCase().contains('healthy') // Make check less strict
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.grey.withOpacity(0.2),
                                        spreadRadius: 1,
                                        blurRadius: 3,
                                        offset: const Offset(0, 2)
                                    )
                                  ]
                                ),
                                child: Text(
                                  // Display label and confidence
                                  'Result: ${_output!.keys.first} (${(_output!.values.first * 100).toStringAsFixed(1)}%)',
                                  style: TextStyle(
                                    fontSize: 18, // Slightly smaller
                                    fontWeight: FontWeight.bold,
                                    color: _output!.keys.first.toLowerCase().contains('healthy')
                                        ? Colors.green.shade900
                                        : Colors.red.shade900,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : const SizedBox.shrink(), // Show nothing if no output
                         ),
                         // Placeholder text when image selected but no result yet (or error)
                         if (_image != null && _output == null && !_loading)
                           Padding(
                             padding: const EdgeInsets.only(top: 10.0),
                             child: Text("Processing...", style: TextStyle(color: Colors.grey.shade600)),
                           )
                         else if (_image == null && !_loading && _modelLoaded)
                           Padding(
                             padding: const EdgeInsets.only(top: 10.0),
                             child: Text("Select an image using buttons below", style: TextStyle(color: Colors.grey.shade600)),
                           ),

                      ],
                    ),
                  ),
                ),

                // Buttons Area
                Padding(
                  padding: const EdgeInsets.only(bottom: 30, left: 24, right: 24, top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Camera Button
                      ElevatedButton.icon(
                        onPressed: (_loading || !_modelLoaded) ? null : () => _pickAndProcessImage(ImageSource.camera), // Disable if loading/model not ready
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Camera'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          textStyle: const TextStyle(fontSize: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                      ),
                      // Gallery Button
                      ElevatedButton.icon(
                        onPressed: (_loading || !_modelLoaded) ? null : () => _pickAndProcessImage(ImageSource.gallery), // Disable if loading/model not ready
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                           textStyle: const TextStyle(fontSize: 16),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
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