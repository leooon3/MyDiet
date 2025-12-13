import 'package:flutter/material.dart';
import '../models/pantry_item.dart';

class PantryView extends StatefulWidget {
  final List<PantryItem> pantryItems;
  final Function(String name, double qty, String unit) onAddManual;
  final Function(int index) onRemove;
  final VoidCallback onScanTap;

  const PantryView({
    super.key,
    required this.pantryItems,
    required this.onAddManual,
    required this.onRemove,
    required this.onScanTap,
  });

  @override
  State<PantryView> createState() => _PantryViewState();
}

class _PantryViewState extends State<PantryView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();
  String _unit = 'g';

  void _handleAdd() {
    if (_nameController.text.isNotEmpty) {
      double qty =
          double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 1.0;
      widget.onAddManual(_nameController.text.trim(), qty, _unit);
      _nameController.clear();
      _qtyController.clear();
      FocusScope.of(context).unfocus(); // Chiude la tastiera
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onScanTap,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text("Scan Scontrino"),
        // Use Secondary (Orange) to encourage scanning
        backgroundColor: Theme.of(context).colorScheme.secondary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- AREA INPUT ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: "Cibo (es. Pasta)",
                      prefixIcon: Icon(Icons.edit_note, color: Colors.grey),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: "0",
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _unit,
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Colors.green,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'g', child: Text("g")),
                        DropdownMenuItem(value: 'pz', child: Text("pz")),
                      ],
                      onChanged: (val) => setState(() => _unit = val!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _handleAdd,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    // Use Primary (Green) for standard add action
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- GRIGLIA PRODOTTI ---
          Expanded(
            child: widget.pantryItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.kitchen_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "La dispensa è vuota",
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: widget.pantryItems.length,
                    itemBuilder: (context, index) {
                      final item = widget.pantryItems[index];
                      bool isLow = item.quantity < 2;

                      String initial = item.name.isNotEmpty
                          ? item.name[0].toUpperCase()
                          : "?";

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.grey[300],
                                ),
                                onPressed: () => widget.onRemove(index),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isLow
                                        ? Colors.orange[50]
                                        : Colors.green[50],
                                    radius: 18,
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        color: isLow
                                            ? Colors.orange
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    "${item.quantity.toInt()} ${item.unit}",
                                    style: TextStyle(
                                      color: isLow
                                          ? Colors.orange
                                          : Colors.green[700],
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
