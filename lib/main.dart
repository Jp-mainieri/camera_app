import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final initialUser = FirebaseAuth.instance.currentUser;
  runApp(MyApp(initialUser: initialUser));
}

class MyApp extends StatelessWidget {
  final User? initialUser;
  const MyApp({super.key, required this.initialUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: initialUser != null ? const CameraScreen() : const LoginScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  XFile? imageFile;
  String? uploadedImageUrl;
  String? _cameraError;
  bool _isUploading = false;
  bool _isTakingPicture = false;
  bool _isSigninOut = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraError = 'Nenhuma camera encontrada neste dispositivo.';
        });
        return;
      }

      _controller = CameraController(cameras.first, ResolutionPreset.high);
      await _controller!.initialize();

      if (!mounted) return;
      setState(() {});
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Erro ao iniciar a camera: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Erro ao iniciar a camera: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      setState(() {
        imageFile = file;
        uploadedImageUrl = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao tirar foto: ${e.description ?? e.code}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  Future<void> _uploadToFirebase() async {
    if (imageFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Usuário não encontrado')));
        return;
      }
      final uid = user.uid;
      final storageRef = FirebaseStorage.instance.ref('$uid/$fileName');
      await storageRef.putFile(
        File(imageFile!.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await storageRef.getDownloadURL();

      if (!mounted) return;
      setState(() {
        uploadedImageUrl = downloadUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload concluido com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha no upload: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera App')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_cameraError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera App'),
        actions: [
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: imageFile == null
                ? CameraPreview(_controller!)
                : Image.file(File(imageFile!.path)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (imageFile == null)
                ElevatedButton(
                  onPressed: _isTakingPicture ? null : _takePicture,
                  child: _isTakingPicture
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Tirar Foto'),
                )
              else ...[
                ElevatedButton(
                  onPressed: _isUploading
                      ? null
                      : () => setState(() {
                          imageFile = null;
                          uploadedImageUrl = null;
                        }),
                  child: const Text('Tirar Outra'),
                ),
                ElevatedButton(
                  onPressed: _isUploading ? null : _uploadToFirebase,
                  child: _isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Upload'),
                ),
              ],
            ],
          ),
          if (uploadedImageUrl != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                uploadedImageUrl!,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _loginError;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Por favor, preencha todos os campos.')),
      );
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final userCrendential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
      if (!mounted) return;
      _showUserInfo(userCrendential.user);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'user-not-found') _loginError = 'Usuário não encontrado.';
      if (e.code == 'wrong-password') _loginError = 'Senha incorreta.';
      if (e.code == 'invalid-email') _loginError = 'Email inválido.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loginError ?? 'Ocorreu um erro ao fazer login.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showUserInfo(User? user) async {
    try {
      if (user == null) {
        if (!mounted) return;
        throw Error();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Usuário autenticado:\nuid: ${user.uid} \nemail: ${user.email}',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao encontrar usuário')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'EMAIL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(),
                      )
                    : const Text('Entrar', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
