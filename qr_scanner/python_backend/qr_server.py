import cv2
import numpy as np
from pyzbar.pyzbar import decode
import json
import socket
import threading
import time
import msgpack
import logging
import os
import sys
import traceback
from typing import List, Dict, Any

# Get the absolute path to the log file
log_file_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'qr_server.log')
ready_file_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'server_ready')

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file_path, mode='w'),  # Overwrite log file on each run
        logging.StreamHandler(sys.stdout)  # Also log to console
    ]
)
logger = logging.getLogger(__name__)

logger.info(f"Log file path: {log_file_path}")
logger.info(f"Ready file path: {ready_file_path}")

class QRServer:
    def __init__(self, host: str = '127.0.0.1', port: int = 5000):
        self.host = host
        self.port = port
        self.server_socket = None
        self.running = False
        self.clients = []
        self.frame_buffer = []
        self.max_buffer_size = 5
        self.processing_thread = None
        
        # Remove ready file if it exists
        if os.path.exists(ready_file_path):
            try:
                os.remove(ready_file_path)
                logger.info("Removed existing ready file")
            except Exception as e:
                logger.error(f"Failed to remove ready file: {e}")
        
        logger.info(f"QR Server initialized with host={host}, port={port}")

    def start(self):
        """Start the QR server and begin listening for connections."""
        try:
            logger.info("Creating server socket...")
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            
            logger.info(f"Binding to {self.host}:{self.port}...")
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(5)
            self.running = True
            
            logger.info(f"QR Server started on {self.host}:{self.port}")
            
            # Create ready file to signal that the server is running
            try:
                with open(ready_file_path, 'w') as f:
                    f.write(f"{self.host}:{self.port}")
                logger.info("Ready file created successfully")
            except Exception as e:
                logger.error(f"Failed to create ready file: {e}")
                raise
            
            # Start processing thread
            logger.info("Starting processing thread...")
            self.processing_thread = threading.Thread(target=self._process_frames)
            self.processing_thread.start()
            logger.info("Processing thread started")
            
            # Accept connections
            logger.info("Starting to accept connections...")
            while self.running:
                try:
                    client_socket, address = self.server_socket.accept()
                    logger.info(f"New connection from {address}")
                    client_thread = threading.Thread(
                        target=self._handle_client,
                        args=(client_socket,)
                    )
                    client_thread.start()
                    self.clients.append(client_socket)
                except Exception as e:
                    logger.error(f"Error accepting connection: {e}")
                    logger.error(traceback.format_exc())
        except Exception as e:
            logger.error(f"Failed to start server: {e}")
            logger.error(traceback.format_exc())
            if os.path.exists(ready_file_path):
                try:
                    os.remove(ready_file_path)
                except:
                    pass
            raise

    def stop(self):
        """Stop the QR server and clean up resources."""
        logger.info("Stopping server...")
        self.running = False
        if self.server_socket:
            self.server_socket.close()
        for client in self.clients:
            client.close()
        if self.processing_thread:
            self.processing_thread.join()
        if os.path.exists(ready_file_path):
            try:
                os.remove(ready_file_path)
            except:
                pass
        logger.info("Server stopped")

    def _handle_client(self, client_socket: socket.socket):
        """Handle communication with a single client."""
        unpacker = msgpack.Unpacker()
        try:
            while self.running:
                # Receive frame data
                data = client_socket.recv(1024 * 1024)  # 1MB buffer
                if not data:
                    break
                
                # Feed the data into the unpacker
                unpacker.feed(data)
                for frame_data in unpacker:
                    logger.info(f"Received frame data of type: {frame_data.get('type')}")
                    if frame_data.get('type') == 'frame':
                        image_data = frame_data.get('data')
                        if image_data:
                            logger.info(f"Frame size: {len(image_data)} bytes")
                            self.frame_buffer.append(image_data)
                            if len(self.frame_buffer) > self.max_buffer_size:
                                self.frame_buffer.pop(0)
                    else:
                        logger.warning(f"Unknown frame type: {frame_data.get('type')}")
        except Exception as e:
            logger.error(f"Error in client handler: {e}")
            logger.error(traceback.format_exc())
        finally:
            client_socket.close()
            self.clients.remove(client_socket)
            logger.info("Client disconnected")

    def _process_frames(self):
        """Process frames from the buffer and detect QR codes."""
        while self.running:
            if not self.frame_buffer:
                time.sleep(0.01)  # Small delay to prevent CPU spinning
                continue
            
            frame_data = self.frame_buffer.pop(0)
            try:
                # Convert frame data to numpy array
                nparr = np.frombuffer(frame_data, np.uint8)
                frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                if frame is None:
                    logger.error("Failed to decode image")
                    continue
                
                logger.info(f"Processing frame of shape: {frame.shape}")
                
                # Convert to grayscale for better QR detection
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                
                # Apply some image processing to improve QR detection
                blurred = cv2.GaussianBlur(gray, (5, 5), 0)
                _, threshold = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                
                # Detect QR codes on both original and processed images
                qr_codes = decode(frame) or decode(threshold)
                logger.info(f"Found {len(qr_codes)} QR codes")
                
                results = []
                for qr in qr_codes:
                    # Clean and format the QR data
                    qr_data = qr.data.decode('utf-8').strip()
                    if qr_data:  # Only process non-empty QR codes
                        result = {
                            'data': qr_data,
                            'type': qr.type,
                            'rect': {
                                'left': int(qr.rect.left),
                                'top': int(qr.rect.top),
                                'width': int(qr.rect.width),
                                'height': int(qr.rect.height)
                            },
                            'polygon': [[int(p.x), int(p.y)] for p in qr.polygon],
                            'timestamp': time.time()
                        }
                        results.append(result)
                        logger.info(f"Detected QR code: {qr_data}")
                
                # Send results to all connected clients if we have valid QR codes
                if results:
                    try:
                        response = msgpack.packb({
                            'type': 'qr_results',
                            'data': results,
                            'timestamp': time.time()
                        })
                        
                        # Make a copy of clients list to avoid modification during iteration
                        current_clients = self.clients.copy()
                        for client in current_clients:
                            try:
                                client.sendall(response)  # Use sendall to ensure complete message is sent
                                logger.info(f"Sent QR results to client: {results}")
                            except Exception as e:
                                logger.error(f"Error sending results to client: {e}")
                                try:
                                    self.clients.remove(client)
                                except ValueError:
                                    pass  # Client already removed
                    except Exception as e:
                        logger.error(f"Error packing QR results: {e}")
            
            except Exception as e:
                logger.error(f"Error processing frame: {e}")
                logger.error(traceback.format_exc())

if __name__ == "__main__":
    logger.info("Starting QR Server...")
    server = QRServer()
    try:
        server.start()
    except KeyboardInterrupt:
        logger.info("Shutting down server...")
        server.stop()
    except Exception as e:
        logger.error(f"Server crashed: {e}")
        logger.error(traceback.format_exc())
        server.stop()
        sys.exit(1) 