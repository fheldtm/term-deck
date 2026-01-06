import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:term_deck/models/ssh_connection.dart';
import 'package:term_deck/theme/app_theme.dart';
import 'package:term_deck/screens/home_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  // Port has default value '22', all other fields empty
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  List<SSHConnectionConfig> _savedConnections = [];
  int? _selectedConnectionIndex;

  @override
  void initState() {
    super.initState();
    _loadSavedConnections();
  }

  Future<void> _loadSavedConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = prefs.getStringList('saved_connections') ?? [];

    setState(() {
      _savedConnections = connectionsJson
          .map((json) => SSHConnectionConfig.fromJson(jsonDecode(json)))
          .toList();
    });

    // Don't auto-load last connection - keep form empty
  }

  Future<void> _saveConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = _savedConnections
        .map((c) => jsonEncode(c.toJson()))
        .toList();
    await prefs.setStringList('saved_connections', connectionsJson);
  }

  void _selectConnection(int index) {
    final conn = _savedConnections[index];
    setState(() {
      _selectedConnectionIndex = index;
      _nameController.text = conn.name;
      _hostController.text = conn.host;
      _portController.text = conn.port.toString();
      _usernameController.text = conn.username;
      _passwordController.text = conn.password ?? '';
    });
  }

  Future<void> _saveCurrentConnection() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.isEmpty
        ? '${_usernameController.text}@${_hostController.text}'
        : _nameController.text;

    final config = SSHConnectionConfig(
      name: name,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text,
      password: _passwordController.text.isEmpty ? null : _passwordController.text,
    );

    setState(() {
      if (_selectedConnectionIndex != null) {
        _savedConnections[_selectedConnectionIndex!] = config;
      } else {
        _savedConnections.add(config);
        _selectedConnectionIndex = _savedConnections.length - 1;
      }
    });

    await _saveConnections();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection saved'),
          backgroundColor: AppColors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _deleteConnection(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface0,
        title: const Text('Delete Connection?', style: TextStyle(color: AppColors.text)),
        content: Text(
          'Delete "${_savedConnections[index].name}"?',
          style: const TextStyle(color: AppColors.subtext0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _savedConnections.removeAt(index);
        if (_selectedConnectionIndex == index) {
          _selectedConnectionIndex = null;
          _clearForm();
        } else if (_selectedConnectionIndex != null && _selectedConnectionIndex! > index) {
          _selectedConnectionIndex = _selectedConnectionIndex! - 1;
        }
      });
      await _saveConnections();
    }
  }

  void _clearForm() {
    _nameController.clear();
    _hostController.clear();
    _portController.text = '22';
    _usernameController.clear();
    _passwordController.clear();
    setState(() => _selectedConnectionIndex = null);
  }

  void _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Save last used connection index
    final prefs = await SharedPreferences.getInstance();
    if (_selectedConnectionIndex != null) {
      await prefs.setInt('last_connection_index', _selectedConnectionIndex!);
    }

    final config = SSHConnectionConfig(
      name: _nameController.text.isEmpty
          ? '${_usernameController.text}@${_hostController.text}'
          : _nameController.text,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text,
      password: _passwordController.text.isEmpty ? null : _passwordController.text,
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(config: config),
        ),
      );
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Saved connections list (collapsible)
        if (_savedConnections.isNotEmpty) ...[
          ExpansionTile(
            title: const Text(
              'Saved Connections',
              style: TextStyle(color: AppColors.text, fontSize: 14),
            ),
            leading: const Icon(Icons.bookmark, color: AppColors.blue),
            initiallyExpanded: true,
            children: [
              SizedBox(
                height: 150,
                child: _buildConnectionsList(),
              ),
            ],
          ),
          const Divider(color: AppColors.surface1, height: 1),
        ],
        // Connection form
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildConnectionForm(),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Saved connections sidebar
        Container(
          width: 280,
          color: AppColors.mantle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.crust,
                child: Row(
                  children: [
                    const Icon(Icons.bookmark, color: AppColors.blue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Saved Connections',
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: _clearForm,
                      tooltip: 'New connection',
                      style: IconButton.styleFrom(foregroundColor: AppColors.green),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildConnectionsList()),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.surface1),
        // Connection form
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _buildConnectionForm(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionsList() {
    if (_savedConnections.isEmpty) {
      return const Center(
        child: Text(
          'No saved connections',
          style: TextStyle(color: AppColors.subtext0),
        ),
      );
    }

    return ListView.builder(
      itemCount: _savedConnections.length,
      itemBuilder: (context, index) {
        final conn = _savedConnections[index];
        final isSelected = _selectedConnectionIndex == index;

        return ListTile(
          dense: true,
          selected: isSelected,
          selectedTileColor: AppColors.surface0.withValues(alpha: 0.5),
          leading: Icon(
            Icons.computer,
            size: 20,
            color: isSelected ? AppColors.blue : AppColors.subtext0,
          ),
          title: Text(
            conn.name,
            style: TextStyle(
              color: isSelected ? AppColors.blue : AppColors.text,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${conn.username}@${conn.host}:${conn.port}',
            style: const TextStyle(color: AppColors.subtext0, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _deleteConnection(index),
            style: IconButton.styleFrom(foregroundColor: AppColors.red),
          ),
          onTap: () => _selectConnection(index),
          onLongPress: () => _deleteConnection(index),
        );
      },
    );
  }

  Widget _buildConnectionForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo/Title
          const Icon(Icons.terminal, size: 48, color: AppColors.blue),
          const SizedBox(height: 12),
          const Text(
            'SSH Terminal',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // Connection name
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Connection Name (optional)',
              hintText: 'e.g., My Server',
              prefixIcon: Icon(Icons.label, color: AppColors.subtext0),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Host field
          TextFormField(
            controller: _hostController,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Host',
              hintText: 'e.g., 192.168.1.100',
              prefixIcon: Icon(Icons.dns, color: AppColors.subtext0),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Port field
          TextFormField(
            controller: _portController,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Port',
              prefixIcon: Icon(Icons.numbers, color: AppColors.subtext0),
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              final port = int.tryParse(value);
              if (port == null || port < 1 || port > 65535) return 'Invalid';
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Username field
          TextFormField(
            controller: _usernameController,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person, color: AppColors.subtext0),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Password field
          TextFormField(
            controller: _passwordController,
            style: const TextStyle(color: AppColors.text),
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password (optional)',
              prefixIcon: const Icon(Icons.lock, color: AppColors.subtext0),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  color: AppColors.subtext0,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 24),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saveCurrentConnection,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _connect,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.base),
                        )
                      : const Icon(Icons.login, size: 18),
                  label: const Text('Connect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: AppColors.base,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
